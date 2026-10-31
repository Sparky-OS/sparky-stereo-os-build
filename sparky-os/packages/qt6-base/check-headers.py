#!/usr/bin/env python3
# Sparky Stereo OS: checks the headers of the installed qt6-base packages, as a program built against them sees them.
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
"""check-headers.py RESULTS: two checks on the installed qt6-base development packages.

1. Each public module header (a module with its Qt6<Module>.pc file, the module header <QtX> that qt6-base-dev ships)
   compiles on its own with the flags pkg-config gives, and all of them compile together in one translation unit.
2. Every #include that the preprocessor reaches, in every header the qt6-base packages install under /usr/include,
   resolves to a file on the system: GCC's -M -MG lists the included files and names a missing one instead of
   stopping, so a header that includes a file no package ships is found wherever it is. The search path is what the
   packages' own pkg-config files and CMake targets give (the module folders, their version folders for the private
   headers, Qt6Platform's mkspecs folder). A header that stops with its own #error when it is included alone ("include
   qcompare.h instead") counts when another installed header reaches it. The includes Qt 6.11.2 itself leaves
   unresolved in its private headers, the same in Debian's build, are listed in check-headers-known.txt; any other fails.
Writes RESULTS/summary.txt and one log per failing case; exits 1 when a check fails."""
import concurrent.futures
import os
import re
import subprocess
import sys
from pathlib import Path

REQUIRED = ['QtCore', 'QtGui', 'QtWidgets', 'QtDBus', 'QtNetwork', 'QtConcurrent', 'QtSql', 'QtXml', 'QtOpenGL', 'QtTest']
CXX = ['g++', '-std=c++17', '-fPIC']

results = Path(sys.argv[1])
results.mkdir(parents=True, exist_ok=True)
multiarch = subprocess.run(['gcc', '-print-multiarch'], capture_output=True, text=True, check=True).stdout.strip()
qtinc = Path('/usr/include') / multiarch / 'qt6'
summary = []
failed = False


def say(line=''):
    print(line, flush=True)
    summary.append(line)


installed = subprocess.run(['dpkg-query', '-W', '-f', '${binary:Package}\t${source:Package}\t${Version}\t${db:Status-Status}\n'],
                           capture_output=True, text=True, check=True).stdout.splitlines()
packages = sorted((p.split(':')[0], v) for p, s, v, st in (l.split('\t') for l in installed) if s == 'qt6-base' and st == 'installed')
say('qt6-base packages installed: ' + ', '.join(f'{p} {v}' for p, v in packages))
owner = {}
for package, _ in packages:
    for line in subprocess.run(['dpkg-query', '-L', package], capture_output=True, text=True, check=True).stdout.splitlines():
        if line.startswith('/usr/include/') and os.path.isfile(line) and not os.path.islink(line):
            owner[line] = package
headers = sorted(owner)
say(f'headers installed by them under /usr/include: {len(headers)}')

dev = {line for line in subprocess.run(['dpkg-query', '-L', 'qt6-base-dev'], capture_output=True, text=True, check=True).stdout.splitlines()}
modules = sorted(d.name for d in qtinc.iterdir() if d.is_dir() and str(d / d.name) in dev)
public = [m for m in modules if subprocess.run(['pkg-config', '--exists', 'Qt6' + m[2:]]).returncode == 0]
say('module headers in qt6-base-dev: ' + ' '.join(modules))
say('public (with a pkg-config file): ' + ' '.join(public))
missing_required = [m for m in REQUIRED if m not in public]
if missing_required:
    say('FAIL required public modules missing: ' + ' '.join(missing_required))
    failed = True


def cflags(names):
    out = subprocess.run(['pkg-config', '--cflags'] + ['Qt6' + m[2:] for m in names], capture_output=True, text=True, check=True)
    return out.stdout.split()


def compile_unit(name, includes, flags):
    source = ''.join(f'#include <{m}>\n' for m in includes)
    run = subprocess.run(CXX + ['-fsyntax-only', '-x', 'c++', '-'] + flags, input=source, capture_output=True, text=True)
    if run.returncode != 0:
        (results / f'compile-{name}.log').write_text(source + '\n' + run.stderr)
    first = next((l for l in run.stderr.splitlines() if 'error' in l), '')
    return run.returncode == 0, first


say()
say('1. module headers')
for module in public:
    ok, first = compile_unit(module, [module], cflags([module]))
    say(f'  {"PASS" if ok else "FAIL"} #include <{module}>' + ('' if ok else f': {first}'))
    failed |= not ok
ok, first = compile_unit('all', public, cflags(public))
say(f'  {"PASS" if ok else "FAIL"} one translation unit with all {len(public)}' + ('' if ok else f': {first}'))
failed |= not ok

say()
say('2. every #include in every installed header')
known = {}
for line in (Path(__file__).parent / 'check-headers-known.txt').read_text().splitlines():
    if line and not line.startswith('#'):
        header, name, reason = line.split('\t')
        known[(str(qtinc / header), name)] = reason
version_dirs = []
for module in sorted(d for d in qtinc.iterdir() if d.is_dir()):
    for v in sorted(p for p in module.iterdir() if p.is_dir() and re.fullmatch(r'\d+\.\d+\.\d+', p.name)):
        version_dirs += ['-I', str(v), '-I', str(v / module.name)]
# Qt6Platform names the mkspecs folder (qplatformdefs.h); the libraries the private headers include from a folder of
# their own are found as their own pkg-config files say (test-in-container.sh installs their development packages)
platform = subprocess.run(['pkg-config', '--cflags-only-I', 'Qt6Platform', 'atspi-2', 'freetype2', 'libdrm'],
                          capture_output=True, text=True, check=True).stdout.split()
search = ['-I', str(qtinc)] + [x for m in sorted(d for d in qtinc.iterdir() if d.is_dir()) for x in ('-I', str(m))] + version_dirs + platform


def deps(header):
    run = subprocess.run(CXX + ['-M', '-MG', '-x', 'c++', '-'] + search, input=f'#include "{header}"\n', capture_output=True, text=True)
    names = run.stdout.replace('\\\n', ' ').split(':', 1)[-1].split()
    found = {n for n in names if n.startswith('/') and os.path.isfile(n)}
    missing = sorted({n for n in names if n != '-' and n not in found})
    errors = [l for l in run.stderr.splitlines() if 'error' in l]
    return header, found, missing, run.returncode, errors


unresolved = {}
stopped = {}
reached = set()
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for header, found, missing, code, errors in pool.map(deps, headers):
        for name in missing:
            unresolved.setdefault(name, []).append(header)
        if code == 0:
            reached |= {os.path.realpath(f) for f in found if os.path.realpath(f) != os.path.realpath(header)}
        elif not missing:
            stopped[header] = errors[:2]
say(f'  headers preprocessed: {len(headers)}')
text = {h: Path(h).read_text(errors='replace') for h in headers}
seen_known = set()
bad = 0
for name in sorted(unresolved):
    pattern = re.compile(r'^\s*#\s*include\s*[<"]' + re.escape(name) + r'[>"]', re.M)
    direct = [h for h in headers if pattern.search(text[h])]
    reasons = [known.get((h, name)) for h in direct]
    if direct and all(reasons):
        seen_known |= {(h, name) for h in direct}
        say(f'  KNOWN {name} ({", ".join(direct)}): {reasons[0]}')
        continue
    say(f'  FAIL {name} does not resolve; included by {", ".join(direct) or "(a computed include)"}'
        f' ({", ".join(sorted({owner[h] for h in direct})) or "?"}), reached from {len(unresolved[name])} installed headers')
    bad += 1
covered = 0
for header, errors in sorted(stopped.items()):
    if os.path.realpath(header) in reached:
        covered += 1
        continue
    if (header, '#error') in known:
        seen_known.add((header, '#error'))
        say(f'  KNOWN {header} stops on its own #error and no installed header includes it: {known[(header, "#error")]}')
        continue
    say(f'  FAIL {header} ({owner[header]}) does not preprocess on its own and no installed header reaches it: {" | ".join(errors)}')
    bad += 1
for header, name in sorted(set(known) - seen_known):
    say(f'  NOTE no longer seen: {header} including {name}')
say(f'  headers that stop on their own #error and are reached from another installed header: {covered}')
say(f'  {"PASS" if not bad else "FAIL"} every other include resolves ({len(headers)} headers, {len(seen_known)} known upstream cases)')
failed |= bool(bad)

say()
say('RESULT: ' + ('FAIL' if failed else 'PASS'))
(results / 'summary.txt').write_text('\n'.join(summary) + '\n')
sys.exit(1 if failed else 0)
