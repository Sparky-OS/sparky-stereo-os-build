# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Native source projection for disposable Debian builds, with exact authored recovery."""
import argparse
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path

from . import VERSION, lang_c, project

EXCLUDED = {'.git', '.pc', 'debian', '.sparky-lc', 'build'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def project_tree(root):
    evidence = root / '.sparky-lc'
    report = evidence / 'source.json'
    if report.exists():
        obj = json.loads(report.read_text())
        if obj['engine'] != VERSION or not obj.get('qualified'):
            raise ValueError('Engine changed or incomplete projection; restore and start a fresh build')
        for name, row in obj['files'].items():
            if sha((root / name).read_bytes()) != row['final_sha256']:
                raise ValueError(f'Source changed after projection: {name}')
        return
    evidence.mkdir(exist_ok=True)
    records = {}
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        if (path.is_symlink() or not path.is_file() or path.suffix.lower() not in lang_c.EXTS
                or any(p in EXCLUDED or p.startswith('obj-') for p in rel.parts)):
            continue
        raw = path.read_bytes()
        metadata = path.stat()
        result = project.project('/' + rel.as_posix(), raw, package='native-build', pointer=False)
        row = asdict(result)
        row.pop('lean')
        row['final_sha256'] = sha(result.lean if result.lean is not None else raw)
        row['source_mtime_ns'] = metadata.st_mtime_ns
        records[rel.as_posix()] = row
        if result.status == 'projected':
            original = evidence / 'authored' / rel
            original.parent.mkdir(parents=True, exist_ok=True)
            original.write_bytes(raw)
            path.write_bytes(result.lean)
            os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
        if result.reason.startswith(('check failed:', 'the c reader', 'not stable')):
            # Retain recovery records even when qualification fails.
            report.write_text(json.dumps({'engine': VERSION, 'files': records}, indent=2) + '\n')
            raise ValueError(f'{rel}: {result.reason}')
    report.write_text(json.dumps({'engine': VERSION, 'qualified': True,
                                 'options': 'collapse-blank,no-pointer,C/C++ line directives',
                                 'stage': 'before compilation', 'files': records}, indent=2) + '\n')
    print(f'Native Lean Code: {sum(r["status"] == "projected" for r in records.values())}/{len(records)} files projected')


def authored(root):
    evidence = root / '.sparky-lc'
    report = evidence / 'source.json'
    if not report.exists():
        return []
    out = []
    for name, row in json.loads(report.read_text())['files'].items():
        if row['status'] != 'projected':
            continue
        raw = (evidence / 'authored' / name).read_bytes()
        if sha(raw) != row['sha_in']:
            raise ValueError(f'Authored recovery copy changed: {name}')
        out.append((name, row, raw))
    return out


def restore_tree(root):
    for name, row, raw in authored(root):
        path = root / name
        if sha(path.read_bytes()) not in (row['final_sha256'], row['sha_in']):
            raise ValueError(f'Refusing to overwrite modified source: {name}')
        path.write_bytes(raw)
        os.utime(path, ns=(path.stat().st_atime_ns, row['source_mtime_ns']))


def restore_payload(root, staging):
    """After installation, restore copied headers before the distinct payload projection.

    Do not restore the compilation tree before dh_auto_install: older debhelper
    invokes make/ninja install and may rebuild it. Refuse ambiguous HR mappings.
    """
    by_hash = {}
    for name, row, raw in authored(root):
        by_hash.setdefault(row['final_sha256'], []).append((name, raw))
    restored = 0
    for path in staging.rglob('*'):
        if path.is_symlink() or not path.is_file() or 'DEBIAN' in path.relative_to(staging).parts:
            continue
        candidates = by_hash.get(sha(path.read_bytes()), [])
        if not candidates:
            continue
        named = [(n, raw) for n, raw in candidates if Path(n).name == path.name]
        choices = {raw for _, raw in named or candidates}
        if len(choices) != 1:
            raise ValueError(f'Ambiguous authored mapping for installed file: {path}')
        path.write_bytes(choices.pop())
        restored += 1
    print(f'Restored {restored} installed source files before payload projection')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('project', 'restore', 'restore-payload'))
    parser.add_argument('root', type=Path)
    parser.add_argument('staging', type=Path, nargs='?')
    args = parser.parse_args()
    try:
        if args.action == 'project':
            project_tree(args.root.resolve())
        elif args.action == 'restore':
            restore_tree(args.root.resolve())
        elif args.staging is None:
            parser.error('restore-payload requires STAGING')
        else:
            restore_payload(args.root.resolve(), args.staging.resolve())
    except (ValueError, OSError) as error:
        parser.exit(1, str(error) + '\n')
