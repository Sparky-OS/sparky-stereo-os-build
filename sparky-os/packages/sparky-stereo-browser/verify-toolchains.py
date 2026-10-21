#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Verify every retained compiler-bundle file before browser configuration."""
import hashlib
import json
import os
from pathlib import Path
import sys


def verify(root, manifest):
    root = root.resolve(strict=True)
    data = json.loads(manifest.read_text())
    rows = data['files']
    if not rows:
        raise ValueError('Empty toolchain manifest')
    actual = set()
    for name in data['roots']:
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts or (root / relative).is_symlink():
            raise ValueError(f'Unsafe compiler-bundle root: {name}')
        actual.update(p.relative_to(root).as_posix() for p in (root / relative).rglob('*')
                      if p.is_file() or p.is_symlink())
    if actual != set(rows):
        raise ValueError('Compiler-bundle inventory differs')
    for name, record in rows.items():
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError(f'Unsafe compiler-bundle path: {name}')
        path = root / relative
        if record['kind'] == 'symlink':
            if not path.is_symlink() or os.readlink(path) != record['target']:
                raise ValueError(f'Compiler-bundle link differs: {name}')
            if not path.resolve(strict=True).is_relative_to(root):
                raise ValueError(f'Compiler-bundle link escapes: {name}')
        else:
            if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
                raise ValueError(f'Invalid compiler-bundle file: {name}')
            with path.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            if digest != record['sha256'] or (path.stat().st_mode & 0o777) != record['mode']:
                raise ValueError(f'Compiler-bundle content or mode differs: {name}')
    print(f'Verified {len(rows)} pinned compiler-bundle entries')


if __name__ == '__main__':
    verify(Path(sys.argv[1]), Path(sys.argv[2]))
