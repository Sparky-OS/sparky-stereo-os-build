#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Rebuild a retained native descriptor, refusing payload/control changes."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile


def members(path, option):
    data = subprocess.check_output(['dpkg-deb', option, str(path)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        return {m.name: (m.type.decode("ascii"), m.mode, m.uid, m.gid, m.linkname,
                         hashlib.sha256(archive.extractfile(m).read()).hexdigest() if m.isfile() else '')
                for m in archive}


ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('descriptor', type=Path)
ap.add_argument('scratch', type=Path)
ap.add_argument('--source-dir', type=Path, help='legacy recipe-tree layout; artifacts are emitted to its parent')
ap.add_argument('--comparison', type=Path, help='retain every differing payload/control member as JSON')
ap.add_argument('--compare-only', action='store_true', help='inspect retained outputs without repeating a build')
ap.add_argument('--new-source-build', action='store_true', help='new successor: descriptor directory must contain no reference binaries')
args = ap.parse_args()
if args.new_source_build and (args.compare_only or list(args.descriptor.parent.glob('*.deb'))):
    ap.error('--new-source-build requires an input-only source directory without reference binaries')
source = args.source_dir or args.scratch / 'source'
source.parent.mkdir(parents=True, exist_ok=True)
artifacts = source.parent
if not args.compare_only:
    subprocess.run(['dpkg-source', '--no-copy', '-x', str(args.descriptor), str(source)], check=True)
    subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-b'], cwd=source, check=True)
made = sorted(artifacts.glob('*.deb'))
if not made:
    raise SystemExit('No binary outputs')
differences = []
for path in (() if args.new_source_build else made):
    prior = args.descriptor.parent / path.name
    if not prior.is_file():
        differences.append({'binary': path.name, 'difference': 'no accepted reference archive'})
        continue
    for option in ('--fsys-tarfile', '--ctrl-tarfile'):
        left, right = members(prior, option), members(path, option)
        for name in sorted(set(left) | set(right)):
            if left.get(name) != right.get(name):
                differences.append({'binary': path.name, 'archive': option, 'member': name,
                                    'accepted': left.get(name), 'rebuilt': right.get(name)})
if args.comparison:
    args.comparison.write_text(json.dumps({'descriptor': str(args.descriptor),
        'descriptor_sha256': hashlib.file_digest(args.descriptor.open('rb'), 'sha256').hexdigest(),
        'binaries': [p.name for p in made], 'differences': differences}, indent=2) + '\n')
if differences:
    raise SystemExit(f'{len(differences)} payload/control members differ; accepted references are unchanged')
if args.compare_only:
    print(f'{len(made)} retained binary payload/control member sets match; no receipts modified')
    raise SystemExit(0)
# Legacy native rules can emit a generated HR companion without registering it.
# Register actual outputs, then regenerate genuine binary metadata through dpkg.
entries = source / 'debian/files'
for path in made:
    lines = entries.read_text().splitlines() if entries.exists() else []
    if not any(line.split()[0] == path.name for line in lines):
        subprocess.run(['dpkg-distaddfile', path.name, 'doc' if '-lc-hr_' in path.name else 'misc', 'optional'], cwd=source, check=True)
        if '-lc-hr_' in path.name:
            lines = entries.read_text().splitlines()
            entries.write_text(''.join(line + (' automatic=yes' if line.split()[0] == path.name else '') + '\n' for line in lines))
name = subprocess.check_output(['dpkg-parsechangelog', '-S', 'Source'], cwd=source, text=True).strip()
version = subprocess.check_output(['dpkg-parsechangelog', '-S', 'Version'], cwd=source, text=True).strip().split(':', 1)[-1]
arch = subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip()
for command, suffix in [('dpkg-genbuildinfo', 'buildinfo'), ('dpkg-genchanges', 'changes')]:
    subprocess.run([command, '--build=binary', '-O' + str(artifacts / f'{name}_{version}_{arch}.{suffix}')], cwd=source, check=True)
# A legacy assembly may write a second descriptor while building. Preserve that
# separately; the record must bind the exact descriptor actually extracted here.
for path in list(artifacts.glob('*.dsc')) + list(artifacts.glob('*.tar.*')):
    saved = args.scratch / 'derived-source'
    saved.mkdir(exist_ok=True)
    shutil.move(str(path), saved / path.name)
from inventory import paragraphs
control = next(p for p in paragraphs(args.descriptor.read_text()) if 'Source' in p and 'Version' in p)
for name in [args.descriptor.name] + [line.split()[-1] for line in control.get('Checksums-Sha256', '').splitlines() if line.strip()]:
    original = args.descriptor.parent / name
    if original.resolve() != (artifacts / name).resolve():
        shutil.copy2(original, artifacts / name)
for pattern in ('*.deb', '*.buildinfo', '*.changes'):
    paths = sorted(artifacts.glob(pattern))
    if not paths:
        raise SystemExit(f'Missing native build metadata {pattern}')
    for path in paths:
        shutil.copy2(path, args.descriptor.parent / path.name)
print(f'Native new source build: {len(made)} archives and genuine receipts retained' if args.new_source_build else
      f'Native rebuild: {len(made)} binary payload/control member sets identical; genuine archives and receipts retained')
