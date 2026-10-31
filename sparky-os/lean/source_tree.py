# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Source projection for disposable builds, with exact authored recovery.

C/C++ is the default. A retained language plan explicitly opts a Java build in;
its JDK must be installed before this stage, as for the actual compiler.
"""
import argparse
from dataclasses import asdict
import fnmatch
import hashlib
import json
import os
from pathlib import Path

from . import VERSION, lang_c, project

EXCLUDED = {'.git', '.pc', 'debian', '.sparky-lc', 'build'}
PRESERVE_PLAN = 'debian/sparky-lean-preserve.json'
LANGUAGE_PLAN = 'debian/sparky-lean-languages.json'
PAYLOAD_SOURCE_PLAN = 'debian/sparky-lean-payload-sources.json'
EXTENSIONS = {'c': lang_c.EXTS, 'java': {'.java'}}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def preservation_plan(root):
    path = root / PRESERVE_PLAN
    if not path.exists():
        return {}
    plan = json.loads(path.read_text())
    if not isinstance(plan, dict):
        raise ValueError('Source preservation plan must map relative patterns to reasons')
    for pattern, reason in plan.items():
        if (not isinstance(pattern, str) or not pattern or pattern.startswith('/')
                or '..' in pattern.split('/') or '\\' in pattern
                or not isinstance(reason, str) or not reason.strip()):
            raise ValueError('Source preservation needs a safe relative pattern and a reason')
    return plan


def project_tree(root):
    evidence = root / '.sparky-lc'
    report = evidence / 'source.json'
    plan = preservation_plan(root)
    language_path = root / LANGUAGE_PLAN
    languages = json.loads(language_path.read_text()) if language_path.exists() else ['c']
    if (not isinstance(languages, list) or not languages
            or any(not isinstance(name, str) or name not in EXTENSIONS for name in languages)
            or len(languages) != len(set(languages))):
        raise ValueError('Source language plan must name supported, unique languages: c, java')
    languages = sorted(languages)
    extensions = set().union(*(EXTENSIONS[name] for name in languages))
    if report.exists():
        obj = json.loads(report.read_text())
        if obj['engine'] != VERSION or not obj.get('qualified'):
            raise ValueError('Engine changed or incomplete projection; restore and start a fresh build')
        if obj.get('preserve', {}) != plan:
            raise ValueError('Source preservation plan changed; restore and start a fresh build')
        if obj.get('languages', ['c']) != languages:
            raise ValueError('Source language plan changed; restore and start a fresh build')
        for name, row in obj['files'].items():
            if sha((root / name).read_bytes()) != row['final_sha256']:
                raise ValueError(f'Source changed after projection: {name}')
        return
    paths = []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        if (path.is_symlink() or not path.is_file() or path.suffix.lower() not in extensions
                or any(p in EXCLUDED or p.startswith('obj-') for p in rel.parts)):
            continue
        paths.append(path)
    names = [p.relative_to(root).as_posix() for p in paths]
    for pattern in plan:
        if not any(fnmatch.fnmatchcase(name, pattern) for name in names):
            raise ValueError(f'Source preservation pattern matches no eligible file: {pattern}')
    evidence.mkdir(exist_ok=True)
    records = {}
    for path, name in zip(paths, names):
        rel = path.relative_to(root)
        raw = path.read_bytes()
        metadata = path.stat()
        reasons = [reason for pattern, reason in plan.items()
                   if fnmatch.fnmatchcase(name, pattern)]
        if reasons:
            result = project.Result(path='/' + name, status='left',
                                    reason='additional source consumer: ' + '; '.join(reasons),
                                    bytes_in=len(raw), bytes_out=len(raw), sha_in=sha(raw))
        else:
            result = project.project('/' + name, raw, package='native-build', pointer=False)
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
        if result.reason.startswith(('check failed:', 'the c reader', 'the java reader', 'not stable')):
            # Retain recovery records even when qualification fails.
            report.write_text(json.dumps({'engine': VERSION, 'files': records}, indent=2) + '\n')
            raise ValueError(f'{rel}: {result.reason}')
    report.write_text(json.dumps({'engine': VERSION, 'qualified': True,
                                 'preserve': plan, 'languages': languages,
                                 'options': 'collapse-blank,no-pointer,C/C++ line breaks kept',
                                 'renderer': project.IDENTITY,
                                 'stage': 'before compilation', 'files': records}, indent=2) + '\n')
    print(f'Build-input Lean Code: {sum(r["status"] == "projected" for r in records.values())}/{len(records)} files projected')


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
    by_name = {}
    for name, row, raw in authored(root):
        by_hash.setdefault(row['final_sha256'], []).append((name, raw))
        by_name[name] = raw
    mappings = {}
    plan = root / PAYLOAD_SOURCE_PLAN
    if plan.exists():
        mappings = json.loads(plan.read_text())
        if not isinstance(mappings, dict):
            raise ValueError('Payload source plan must map installed prefixes to source directories')
        for prefix, directory in mappings.items():
            if (not isinstance(prefix, str) or not prefix.startswith('/') or '\\' in prefix
                    or '..' in Path(prefix).parts or Path(prefix).as_posix() != prefix
                    or not isinstance(directory, str) or not directory or directory.startswith('/')
                    or '..' in Path(directory).parts or '\\' in directory):
                raise ValueError('Unsafe payload source mapping')
    source_report = root / '.sparky-lc/source.json'
    records = json.loads(source_report.read_text())['files'] if mappings else {}
    ordered = sorted(mappings, key=len, reverse=True)
    restored = 0
    for path in staging.rglob('*'):
        if path.is_symlink() or not path.is_file() or 'DEBIAN' in path.relative_to(staging).parts:
            continue
        digest = sha(path.read_bytes())
        installed = '/' + path.relative_to(staging).as_posix()
        prefix = next((p for p in ordered if installed.startswith(p.rstrip('/') + '/')), None)
        if prefix is not None:
            relative = installed[len(prefix.rstrip('/')) + 1:]
            name = (Path(mappings[prefix]) / relative).as_posix()
            row = records.get(name)
            if row is not None:
                if digest == row['sha_in']:
                    continue  # includes genuine empty headers, never projected
                if digest != row['final_sha256'] or name not in by_name:
                    raise ValueError(f'Mapped source copy changed during staging: {path}')
                path.write_bytes(by_name[name])
                restored += 1
            # Unknown paths under an explicit copy layout are generated files;
            # do not infer their origin from a coincidental content hash.
            continue
        candidates = by_hash.get(digest, [])
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
