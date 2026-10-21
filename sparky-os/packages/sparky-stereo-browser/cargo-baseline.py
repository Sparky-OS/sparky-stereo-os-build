#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reconcile only recorded vendor metadata discrepancies in the accepted tree.

The baseline records exact files verified against the accepted Git commit. This
is separate from Lean Code: no Rust source or crate package identity is changed.
Keep the upstream checksum manifests in the source archive and restore them on
clean. The projection adapter subsequently verifies its own changes separately.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe(root, name):
    relative = Path(name)
    path = root / relative
    if (relative.is_absolute() or '..' in relative.parts or path.is_symlink()
            or not path.resolve().is_relative_to(root.resolve())):
        raise ValueError(f'Unsafe source path: {name}')
    return path


def apply(root):
    baseline = json.loads((root / 'debian/cargo-baseline.json').read_text())
    origin = json.loads((root / 'SOURCE.edition.json').read_text())
    if baseline['browser_commit'] != origin['browser_commit']:
        raise ValueError('Vendor baseline belongs to a different browser commit')
    state = root / '.sparky-lc'
    state.mkdir(exist_ok=True)
    journal = state / 'cargo-baseline.json'
    if journal.exists():
        for name, row in json.loads(journal.read_text()).items():
            if digest(safe(root, name).read_bytes()) != row['after_sha256']:
                raise ValueError('Restore projected Cargo checksums before the baseline')
        return
    report_path = state / 'source.json'
    report = json.loads(report_path.read_text()) if report_path.exists() else {}
    replacements = {}
    records = {}
    for name, row in baseline['manifests'].items():
        path = safe(root, name)
        original = path.read_bytes()
        if digest(original) != row['sha256']:
            raise ValueError(f'Changed upstream checksum manifest: {name}')
        manifest = json.loads(original)
        for relative, change in row['files'].items():
            if manifest['files'][relative] != change['upstream_sha256']:
                raise ValueError(f'Changed checksum entry: {name}: {relative}')
            target = safe(root, str(Path(name).parent / relative))
            accepted = change['accepted_sha256']
            if accepted is None:
                if target.exists():
                    raise ValueError(f'Expected absent file now exists: {target}')
                del manifest['files'][relative]
                continue
            actual = digest(target.read_bytes())
            if actual != accepted:
                proof = report.get('files', {}).get(target.relative_to(root).as_posix(), {})
                if not (report.get('qualified') and report.get('stage') == 'before compilation'
                        and proof.get('status') == 'projected'
                        and proof.get('sha_in') == accepted
                        and proof.get('final_sha256') == actual):
                    raise ValueError(f'File differs from accepted source: {target}')
            # The second adapter binds accepted source to projected source.
            manifest['files'][relative] = accepted
        updated = (json.dumps(manifest, separators=(',', ':')) + '\n').encode()
        replacements[name] = updated
        records[name] = dict(before=base64.b64encode(original).decode(),
                             after_sha256=digest(updated))
    journal.write_text(json.dumps(records, indent=2) + '\n')
    for name, data in replacements.items():
        safe(root, name).write_bytes(data)
    print(f'Cargo: reconciled {len(records)} manifests against accepted source')


def restore(root):
    journal = root / '.sparky-lc/cargo-baseline.json'
    if not journal.exists():
        return
    records = json.loads(journal.read_text())
    for name, row in records.items():
        original = base64.b64decode(row['before'], validate=True)
        if digest(safe(root, name).read_bytes()) not in (digest(original), row['after_sha256']):
            raise ValueError(f'Refusing to overwrite edited checksum manifest: {name}')
    for name, row in records.items():
        safe(root, name).write_bytes(base64.b64decode(row['before'], validate=True))
    journal.unlink()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['apply', 'restore'])
    args = parser.parse_args()
    try:
        (apply if args.operation == 'apply' else restore)(Path.cwd())
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error)) from error
