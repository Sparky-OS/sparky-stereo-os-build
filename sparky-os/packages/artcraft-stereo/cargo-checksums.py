#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Bind Cargo's vendor checksums to qualified C/C++ build-input changes.

The retained source archive contains Cargo's original vendored files. After
Lean Code projects a disposable build, change only checksum entries proved by
that exact projection report. Rust source and crate identities remain unchanged.
"""
import base64
import argparse
import hashlib
import json
from pathlib import Path
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, relative):
    name = Path(relative)
    if name.is_absolute() or '..' in name.parts:
        raise ValueError(f'Unsafe vendor path: {relative}')
    path = root / name
    if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f'Vendor path leaves its source tree: {relative}')
    return path


def refresh(root, vendor='vendor'):
    root = root.resolve()
    vendor_root = safe_path(root, vendor)
    report = json.loads((root / '.sparky-lc/source.json').read_text())
    if not report.get('qualified') or report.get('stage') != 'before compilation':
        raise ValueError('A qualified pre-compilation report is required')
    journal = root / '.sparky-lc/cargo-checksums.json'
    if journal.exists():
        for relative, row in json.loads(journal.read_text()).items():
            if digest(safe_path(root, relative).read_bytes()) != row['after_sha256']:
                raise ValueError('Vendor checksum update interrupted or changed; restore first')
        return
    changes = {}
    replacements = {}
    for manifest in sorted(vendor_root.glob('*/.cargo-checksum.json')):
        original = manifest.read_bytes()
        obj = json.loads(original)
        changed = False
        for relative, expected in obj['files'].items():
            path = safe_path(manifest.parent, relative)
            actual = digest(path.read_bytes())
            if actual == expected:
                continue
            name = path.relative_to(root).as_posix()
            proof = report['files'].get(name, {})
            if (proof.get('status') != 'projected' or proof.get('sha_in') != expected
                    or proof.get('final_sha256') != actual):
                raise ValueError(f'Vendor content changed without matching projection evidence: {name}')
            obj['files'][relative] = actual
            changed = True
        if changed:
            relative = manifest.relative_to(root).as_posix()
            updated = (json.dumps(obj, sort_keys=True, separators=(',', ':')) + '\n').encode()
            changes[relative] = {'before': base64.b64encode(original).decode(),
                                 'after_sha256': digest(updated)}
            replacements[relative] = updated
    if not list(vendor_root.glob('*/.cargo-checksum.json')):
        raise ValueError('No Cargo vendor checksum manifests found')
    # Validate the complete vendor set before changing any manifest. Recovery
    # data is durable before the first write, including interrupted builds.
    journal.write_text(json.dumps(changes, indent=2) + '\n')
    for relative, updated in replacements.items():
        safe_path(root, relative).write_bytes(updated)
    print(f'Cargo: {len(changes)} checksum manifests bound to qualified source projections')


def restore(root):
    root = root.resolve()
    journal = root / '.sparky-lc/cargo-checksums.json'
    if not journal.exists():
        return
    rows = json.loads(journal.read_text())
    for relative, row in rows.items():
        original = base64.b64decode(row['before'], validate=True)
        if digest(safe_path(root, relative).read_bytes()) not in (digest(original), row['after_sha256']):
            raise ValueError(f'Refusing to overwrite an edited vendor manifest: {relative}')
    for relative, row in rows.items():
        safe_path(root, relative).write_bytes(base64.b64decode(row['before'], validate=True))
    journal.unlink()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['refresh', 'restore'])
    parser.add_argument('--vendor-dir', default='vendor')
    args = parser.parse_args()
    try:
        if args.operation == 'refresh':
            refresh(Path.cwd(), args.vendor_dir)
        else:
            restore(Path.cwd())
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error)) from error
