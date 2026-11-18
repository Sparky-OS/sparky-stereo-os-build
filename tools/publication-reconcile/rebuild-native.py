#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Rebuild a retained native descriptor, refusing payload/control changes."""
import argparse
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import tarfile


def members(path, option):
    data = subprocess.check_output(['dpkg-deb', option, str(path)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        return {m.name: (m.type, m.mode, m.uid, m.gid, m.linkname,
                         hashlib.sha256(archive.extractfile(m).read()).hexdigest() if m.isfile() else '')
                for m in archive}


ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('descriptor', type=Path)
ap.add_argument('scratch', type=Path)
args = ap.parse_args()
source = args.scratch / 'source'
subprocess.run(['dpkg-source', '--no-copy', '-x', str(args.descriptor), str(source)], check=True)
subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-b'], cwd=source, check=True)
made = sorted(args.scratch.glob('*.deb'))
if not made:
    raise SystemExit('No binary outputs')
for path in made:
    prior = args.descriptor.parent / path.name
    for option in ('--fsys-tarfile', '--ctrl-tarfile'):
        if members(path, option) != members(prior, option):
            raise SystemExit(f'{path.name}: retained source changed {option} members')
for pattern in ('*.deb', '*.buildinfo', '*.changes'):
    paths = sorted(args.scratch.glob(pattern))
    if not paths:
        raise SystemExit(f'Missing native build metadata {pattern}')
    for path in paths:
        shutil.copy2(path, args.descriptor.parent / path.name)
print(f'Native rebuild: {len(made)} binary payload/control member sets identical; genuine archives and receipts retained')
