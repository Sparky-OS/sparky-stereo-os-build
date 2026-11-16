#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Rebuild a standalone script source and retain its genuine dpkg build metadata.

The source adapter must reproduce payload and control members. Native compiled
packages use their original source build instead of this adapter.
"""
import argparse
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import tempfile
import tarfile


def members(path, option):
    data = subprocess.check_output(['dpkg-deb', option, str(path)])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        return {m.name: (m.type, m.mode, m.uid, m.gid, m.linkname,
                         hashlib.sha256(archive.extractfile(m).read()).hexdigest() if m.isfile() else '')
                for m in archive}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('descriptor', type=Path)
args = parser.parse_args()
dsc = args.descriptor.resolve()
out = dsc.parent
with tempfile.TemporaryDirectory(prefix='.source-rebuild-', dir=out) as temp:
    work = Path(temp)
    source = work / 'source'
    subprocess.run(['dpkg-source', '--no-copy', '-x', str(dsc), str(source)], check=True)
    if not (source / 'tree-modes.json').is_file():
        raise SystemExit('This is not a standalone script/data source')
    subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-b'], cwd=source, check=True)
    made = sorted(work.glob('*.deb'))
    if not made:
        raise SystemExit('The source rebuild produced no binary archives')
    for binary in made:
        original = out / binary.name
        if not original.is_file() or any(members(binary, kind) != members(original, kind)
                                        for kind in ('--fsys-tarfile', '--ctrl-tarfile')):
            raise SystemExit(f'{binary.name}: source rebuild payload or controls differ from the initial recipe build')
    # Keep the actual source-build archives named by buildinfo and changes.
    # Archive timestamps and compression can differ from the initial assembly.
    for binary in made:
        shutil.copy2(binary, out / binary.name)
    for pattern in ('*.buildinfo', '*.changes'):
        metadata = list(work.glob(pattern))
        if not metadata:
            raise SystemExit(f'The source rebuild produced no {pattern}')
        for item in metadata:
            shutil.copy2(item, out / item.name)
    print(f'Source rebuild: {len(made)} binary payloads and controls equal; rebuilt archives, buildinfo and changes retained')
