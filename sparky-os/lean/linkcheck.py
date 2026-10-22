# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Link and start gate for lc1 packages: a rebuild must still link and load like the build it replaces.

Why this exists (ORDER 198, found 2026-10-22): torcs 1.3.7+dfsg-5+stereo3d1+lc1 was published
and installed although torcs-bin could not start ("undefined symbol XRRConfigCurrentConfiguration
in libtgfclient.so"). The lc1 link dropped libXrandr from NEEDED and libxrandr2 from Depends
because nothing checked that the rebuilt ELF files still resolve every symbol. The payload
hashes of `check-debs` prove the archive bytes, not that the programs run.

Four checks, none installs anything and none needs a display:

  stereo   a symbol with "stereo" in its name that an ELF file imported in the previous build
           and no longer imports: the stereo feature was compiled out (blocks).
  needed   NEEDED libraries and shlib Depends lost against the previous build of the same
           package. Reported; blocks only together with an unresolved symbol (a library
           that is no longer needed because nothing uses it is a legitimate --as-needed result).
  resolve  `ldd -r` on every ELF of the package, with the package's own library directories
           on LD_LIBRARY_PATH (the way its launcher sets it). Every "not found" and every
           "undefined symbol" must already exist in the previous build's result; a package
           without a previous build must have no missing library and no undefined symbol in
           an executable (a library alone reports what its program supplies).
  smoke    start the programs named in a smoke table with LD_BIND_NOW=1 (every symbol is bound
           at load, which is exactly what failed for torcs) and no display; a dynamic-loader
           error in the output blocks.

Run it where the package's runtime dependencies are installed (the build container, a
throwaway container), never on the host. Python 3 only, standard library only.
"""

from __future__ import annotations

import contextlib
import os
from pathlib import Path
import re
import subprocess
import tempfile

from . import package

LOADER_ERRORS = re.compile(
    r'symbol lookup error|undefined symbol|cannot open shared object file|'
    r'error while loading shared libraries|version `[^\']+\' not found')


def _is_elf(path):
    try:
        with open(path, 'rb') as handle:
            return handle.read(4) == b'\x7fELF'
    except OSError:
        return False


def elf_files(root):
    """Regular ELF files of an extracted tree, never following symlinks, debug-symbol files excluded."""
    root = Path(root)
    found = []
    for base, dirs, names in os.walk(root):
        if '/usr/lib/debug' in base[len(str(root)):] + '/':
            dirs[:] = []
            continue
        for name in names:
            path = Path(base) / name
            if not path.is_symlink() and path.is_file() and _is_elf(path):
                found.append(path)
    return sorted(found)


def needed(path):
    out = subprocess.run(['readelf', '-d', '-W', str(path)], capture_output=True, text=True, timeout=30).stdout
    return sorted(line.split('[', 1)[1].rstrip(']') for line in out.splitlines() if '(NEEDED)' in line)


MULTIARCH = {'amd64': 'x86_64-linux-gnu', 'i386': 'i386-linux-gnu', 'arm64': 'aarch64-linux-gnu'}

STEREO = re.compile(r'stereo', re.I)


def stereo_imports(path):
    """Dynamic symbols a file imports whose names mention stereo (stereo_declare_*, libstereo-layer, ...)."""
    out = subprocess.run(['nm', '-D', '--undefined-only', str(path)], capture_output=True, text=True, timeout=60).stdout
    found = set()
    for line in out.splitlines():
        part = line.split()
        if len(part) >= 2 and part[0] == 'U' and STEREO.search(part[-1]):
            found.add(part[-1].split('@')[0])
    return found


def extract(deb, dest):
    subprocess.run(['dpkg-deb', '-x', str(deb), str(dest)], check=True, stdout=subprocess.DEVNULL)


def control_field(deb, field):
    return subprocess.run(['dpkg-deb', '-f', str(deb), field], capture_output=True, text=True, check=True).stdout.strip()


def private_dirs(root):
    """Directories of the tree holding shared objects outside the system multiarch directories."""
    root = Path(root)
    dirs = set()
    for path in elf_files(root):
        if '.so' in path.name:
            rel = '/' + str(path.parent.relative_to(root))
            if rel not in ('/usr/lib', '/lib') and not rel.endswith('-linux-gnu'):
                dirs.add(str(path.parent))
    return sorted(dirs)


@contextlib.contextmanager
def sibling_dirs(debs):
    """Library directories of other packages built from the same source, extracted for the run.

    A plugin links the library its sibling package ships; the build container has not installed it."""
    with tempfile.TemporaryDirectory(prefix='lc-link-sib-') as base:
        dirs = set()
        for index, deb in enumerate(debs):
            root = Path(base) / str(index)
            root.mkdir()
            extract(deb, root)
            dirs.update(str(p.parent) for p in elf_files(root) if '.so' in p.name)
        yield sorted(dirs)


def resolve(root, timeout=20, extra_dirs=()):
    """{(relative file, kind, item): True} for every unresolved library or symbol of the tree."""
    root = Path(root)
    env = dict(os.environ, LD_LIBRARY_PATH=':'.join(private_dirs(root) + list(extra_dirs)))
    result = {}
    for path in elf_files(root):
        rel = '/' + str(path.relative_to(root))
        try:
            run = subprocess.run(['ldd', '-r', str(path)], capture_output=True, text=True, timeout=timeout, env=env)
        except subprocess.TimeoutExpired:
            result[(rel, 'timeout', '')] = True
            continue
        text = run.stdout + run.stderr
        if 'not a dynamic executable' in text:
            continue
        for line in text.splitlines():
            line = line.strip()
            if 'not found' in line:
                result[(rel, 'not found', line.split('=>')[0].strip())] = True
            elif 'undefined symbol' in line:
                symbol = line.split('undefined symbol:', 1)[1].split(',')[0].split('\t')[0].strip()
                result[(rel, 'undefined', symbol)] = True
    return result


def compare(new_deb, previous_deb=None, extra_dirs=()):
    """Return (findings, notes). A finding blocks the release, a note is informational."""
    findings, notes = [], []
    with tempfile.TemporaryDirectory(prefix='lc-link-new-') as new_root:
        extract(new_deb, new_root)
        now = resolve(new_root, extra_dirs=extra_dirs)
        new_needed = {str(p.relative_to(new_root)): needed(p) for p in elf_files(new_root)}
        new_stereo = {str(p.relative_to(new_root)): stereo_imports(p) for p in elf_files(new_root)}
        if previous_deb:
            with tempfile.TemporaryDirectory(prefix='lc-link-old-') as old_root:
                extract(previous_deb, old_root)
                before = resolve(old_root)
                old_needed = {str(p.relative_to(old_root)): needed(p) for p in elf_files(old_root)}
                old_stereo = {str(p.relative_to(old_root)): stereo_imports(p) for p in elf_files(old_root)}
            grouped = {}
            for key in sorted(now):
                if key not in before:
                    grouped.setdefault((key[0], key[1]), []).append(key[2])
            for (name, kind), items in sorted(grouped.items()):
                shown = ', '.join(items[:3]) + (f' and {len(items) - 3} more' if len(items) > 3 else '')
                findings.append(f'{name}: {len(items)} new {kind}: {shown} (the previous build resolved them)')
            # A stereo feature that an optional build dependency switched off compiles and links
            # cleanly (analitza 4:26.04.0-1+stereo3d2+lc1 lost stereo_declare_wayland this way).
            for rel in sorted(set(old_stereo) & set(new_stereo)):
                gone = sorted(old_stereo[rel] - new_stereo[rel])
                if gone:
                    findings.append(f'/{rel}: stereo imports lost: {", ".join(gone[:4])}'
                                    f'{" and more" if len(gone) > 4 else ""} (the previous build called them)')
            for rel in sorted(set(old_needed) & set(new_needed)):
                lost = sorted(set(old_needed[rel]) - set(new_needed[rel]))
                if lost:
                    notes.append(f'{rel}: NEEDED no longer lists {", ".join(lost)}')
            old_dep = _depends(previous_deb)
            new_dep = _depends(new_deb)
            for name in sorted(old_dep - new_dep):
                notes.append(f'Depends no longer names {name}')
        else:
            library_only = {}
            for key in sorted(now):
                is_exec = not re.search(r'\.so(\.|$)', key[0])
                # A library alone reports symbols that its program supplies; only a program
                # or a missing library is a certain failure without a baseline.
                if key[1] != 'undefined' or is_exec:
                    findings.append(f'{key[0]}: {key[1]} {key[2]} (no previous build to compare)')
                else:
                    library_only[key[0]] = library_only.get(key[0], 0) + 1
            for name, count in sorted(library_only.items()):
                notes.append(f'{name}: {count} symbols left to its program (no previous build to compare)')
    return findings, notes


def _depends(deb):
    fields = control_field(deb, 'Depends')
    return {re.split(r'[ (:]', alt.strip())[0] for part in fields.split(',') for alt in part.split('|') if alt.strip()}


def smoke(deb, table, timeout=10, extra_dirs=()):
    """Start every program named for this package in `table` (package TAB path TAB args).
    `{multiarch}` in a path stands for the package architecture's library triplet.

    LD_BIND_NOW=1 binds every symbol at load; DISPLAY and WAYLAND_DISPLAY are removed, so no
    program can reach a desktop. Returns findings."""
    name, arch = control_field(deb, 'Package'), control_field(deb, 'Architecture')
    findings = []
    rows = [line.split('\t') for line in Path(table).read_text().splitlines()
            if line.strip() and not line.startswith('#')]
    with tempfile.TemporaryDirectory(prefix='lc-smoke-') as root:
        extract(deb, root)
        env = {k: v for k, v in os.environ.items() if k not in ('DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY')}
        env['LD_BIND_NOW'] = '1'
        env['LD_LIBRARY_PATH'] = ':'.join(private_dirs(root) + list(extra_dirs))
        for row in rows:
            if row[0] != name:
                continue
            program = row[1].replace('{multiarch}', MULTIARCH.get(arch, arch))
            exe = Path(root) / program.lstrip('/')
            if not exe.is_file():
                findings.append(f'{program}: listed in the smoke table, missing from the package')
                continue
            args = row[2].split() if len(row) > 2 else ['--version']
            try:
                run = subprocess.run([str(exe)] + args, capture_output=True, text=True, timeout=timeout,
                                     env=env, stdin=subprocess.DEVNULL)
                text = run.stdout + run.stderr
            except subprocess.TimeoutExpired as exc:
                text = (exc.stdout or b'').decode(errors='replace') + (exc.stderr or b'').decode(errors='replace')
            if LOADER_ERRORS.search(text):
                findings.append(f'{program}: loader error at start: {text.replace(root, "").strip()[:300]}')
    return findings


def check(new_deb, previous_deb=None, smoke_table=None, extra_dirs=()):
    """`extra_dirs`: library directories of the other packages built from the same source."""
    findings, notes = compare(new_deb, previous_deb, extra_dirs)
    if smoke_table:
        findings += smoke(new_deb, smoke_table, extra_dirs=extra_dirs)
    for note in notes:
        print(f'lc1 link note: {Path(new_deb).name}: {note}')
    if findings:
        raise package.Invalid(f'{Path(new_deb).name}: link check failed:\n  ' + '\n  '.join(findings))
    return notes
