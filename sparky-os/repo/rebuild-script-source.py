#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Rebuild a standalone script source and retain its genuine dpkg build metadata.

The source adapter must reproduce every binary byte for byte. Native compiled
packages use their original source build instead of this adapter.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

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
        if not original.is_file() or hashlib.sha256(binary.read_bytes()).digest() != hashlib.sha256(original.read_bytes()).digest():
            raise SystemExit(f'{binary.name}: source rebuild differs from the initial recipe build')
    for pattern in ('*.buildinfo', '*.changes'):
        metadata = list(work.glob(pattern))
        if not metadata:
            raise SystemExit(f'The source rebuild produced no {pattern}')
        for item in metadata:
            shutil.copy2(item, out / item.name)
    print(f'Source rebuild: {len(made)} binary archives byte-identical; buildinfo and changes retained')
