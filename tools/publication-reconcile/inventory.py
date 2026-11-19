#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read-only bounded package inventory for publication reconciliation.

No producer or cohort module is executed. No input is modified.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def paragraphs(text):
    rows = []
    for block in re.split(r'\n\s*\n', text):
        row, key = {}, None
        for line in block.splitlines():
            if line.startswith((' ', '\t')) and key:
                row[key] += '\n' + line
            elif re.match(r'^[A-Za-z][A-Za-z0-9-]*:', line):
                key, value = line.split(':', 1)
                row[key] = value.strip()
        if row:
            rows.append(row)
    return rows


def source_identity(row):
    name = row.get('Source', row.get('Package', ''))
    match = re.fullmatch(r'([^\s()]+)(?:\s+\(([^)]+)\))?', name)
    if not match:
        raise ValueError(f'bad Source: {name!r}')
    return match[1], match[2] or row['Version']


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def walk(root, depth, errors):
    def failed(error):
        errors.append(str(error))
    for base, dirs, files in os.walk(root, followlinks=False, onerror=failed):
        rel = Path(base).relative_to(root)
        level = 0 if rel == Path('.') else len(rel.parts)
        dirs[:] = sorted(d for d in dirs if d not in ('.git', 'node_modules'))
        if level >= depth:
            dirs[:] = []
        yield Path(base), dirs, sorted(files), level


def inspect(path):
    if path.suffix == '.deb':
        result = subprocess.run(['dpkg-deb', '-f', str(path)], capture_output=True, text=True)
        if result.returncode:
            return {'path': str(path), 'error': result.stderr.strip()}
        fields = paragraphs(result.stdout)[0]
        source, version = source_identity(fields)
        row = {'kind': 'binary', 'binary': fields['Package'], 'version': fields['Version'],
               'architecture': fields['Architecture'], 'source': source, 'source_version': version,
               'lean': fields.get('Sparky-Lean-Code', ''),
               'variant': fields.get('Architecture-Variant', '')}
    else:
        fields = next(r for r in paragraphs(path.read_text()) if 'Source' in r and 'Version' in r)
        row = {'kind': 'source', 'source': fields['Source'], 'source_version': fields['Version'],
               'architecture': fields.get('Architecture', ''), 'components': fields.get('Checksums-Sha256', '')}
    # Archive hashing belongs to qualification; controls suffice for the discovery milestone.
    return dict(row, path=str(path), bytes=path.stat().st_size)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('--published', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--depth', type=int, default=4)
    args = parser.parse_args()
    errors, directories, candidates = [], [], []
    for base, dirs, files, level in walk(args.build_root, args.depth, errors):
        if base.name.startswith('stage') or base.name in ('out', 'superseded', 'predecessor'):
            directories.append(str(base))
        if level + 1 > args.depth:
            continue
        for name in files:
            if name.endswith(('.deb', '.dsc')):
                path = base / name
                if any(p.startswith('stage') or p in ('out', 'superseded', 'predecessor')
                       for p in path.relative_to(args.build_root).parts[:-1]):
                    candidates.append(path)
    # Discovery is bounded from the storage root. Inventory each discovered
    # stage through four relative levels as well, including named subfolders.
    for directory in directories:
        for base, dirs, files, level in walk(Path(directory), args.depth, errors):
            if level + 1 <= args.depth:
                candidates.extend(base / name for name in files if name.endswith(('.deb', '.dsc')))
    candidates = sorted(set(candidates))
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for path, result in zip(candidates, pool.map(inspect, candidates)):
            if 'error' in result:
                errors.append(result['path'] + ': ' + result['error'])
            rows.append(result)
    indexes, published = [], []
    for path in sorted((args.published / 'dists').rglob('*')):
        if path.is_file() and path.name in ('Packages', 'Sources'):
            indexes.append({'path': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size})
            for fields in paragraphs(path.read_text()):
                if path.name == 'Packages':
                    source, version = source_identity(fields)
                    published.append({'kind': 'binary', 'binary': fields['Package'],
                                      'version': fields['Version'], 'source': source,
                                      'source_version': version, 'architecture': fields['Architecture'],
                                      'filename': fields['Filename'], 'sha256': fields.get('SHA256', ''),
                                      'variant': fields.get('Architecture-Variant', '')})
                else:
                    published.append({'kind': 'source', 'source': fields['Package'],
                                      'source_version': fields['Version'], 'directory': fields['Directory']})
    args.output.mkdir(parents=True, exist_ok=True)
    data = {'build_root': str(args.build_root), 'depth': args.depth, 'stage_file_depth': args.depth, 'stage_directories': sorted(directories), 'errors': errors,
            'indexes': indexes, 'published': published, 'staged': rows}
    (args.output / 'inventory.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.output / 'search-errors.txt').write_text('\n'.join(errors) + '\n')
    (args.output / 'stage-directories.txt').write_text('\n'.join(sorted(directories)) + '\n')
    print(json.dumps({'stage_directories': len(directories), 'artifacts': len(rows),
                      'published_records': len(published), 'errors': len(errors)}))


if __name__ == '__main__':
    main()
