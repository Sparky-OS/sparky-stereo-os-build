#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Inventory explicitly named stages and bounded storage without following links."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
from inventory import digest, inspect, paragraphs, source_identity


def walk(root, depth, errors, skipped):
    root = Path(root)
    if any(p.is_symlink() for p in (root, *root.parents)):
        skipped.append(str(root))
        return
    if not root.is_dir():
        errors.append('missing directory: ' + str(root))
        return
    def failed(error):
        errors.append(str(error))
    for base, dirs, files in os.walk(root, followlinks=False, onerror=failed):
        base = Path(base)
        level = len(base.relative_to(root).parts)
        for name in dirs[:] + files[:]:
            if (base / name).is_symlink():
                skipped.append(str(base / name))
        dirs[:] = sorted(d for d in dirs if d not in ('.git', 'node_modules') and not (base / d).is_symlink()) if level < depth else []
        yield base, [f for f in sorted(files) if not (base / f).is_symlink()], level


def discover(roots, stages, depth, errors, skipped):
    directories = set(stages)
    for root in roots:
        for base, files, level in walk(root, depth, errors, skipped):
            if base.name.startswith('stage') or base.name in ('out', 'superseded', 'predecessor'):
                directories.add(str(base))
    candidates = set()
    for directory in sorted(directories):
        for base, files, level in walk(directory, depth, errors, skipped):
            if level < depth:
                candidates.update(base / f for f in files if f.endswith(('.deb', '.dsc')))
    return sorted(directories), sorted(candidates)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, action='append', default=[])
    parser.add_argument('--stages', type=Path, required=True, help='one literal directory per line')
    parser.add_argument('--published', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--depth', type=int, default=4)
    args = parser.parse_args()
    if args.depth < 1:
        parser.error('depth must be positive')
    errors, skipped = [], []
    directories, paths = discover(args.root, args.stages.read_text().splitlines(), args.depth, errors, skipped)
    rows = []
    def guarded(path):
        try:
            return inspect(path)
        except (OSError, ValueError, KeyError, StopIteration) as error:
            return {'path': str(path), 'error': str(error)}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for row in pool.map(guarded, paths):
            rows.append(row)
            if 'error' in row:
                errors.append(row['path'] + ': ' + row['error'])
    indexes, published = [], []
    for base, files, level in walk(args.published / 'dists', 6, errors, skipped):
        for name in files:
            if name not in ('Packages', 'Sources'):
                continue
            path = base / name
            indexes.append({'path': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size})
            for fields in paragraphs(path.read_text()):
                if name == 'Packages':
                    source, version = source_identity(fields)
                    published.append(dict(kind='binary', binary=fields['Package'], version=fields['Version'], source=source,
                                          source_version=version, architecture=fields['Architecture'],
                                          variant=fields.get('Architecture-Variant', ''), filename=fields['Filename'], sha256=fields['SHA256']))
                else:
                    published.append(dict(kind='source', source=fields['Package'], source_version=fields['Version'], directory=fields['Directory']))
    args.output.mkdir(parents=True, exist_ok=True)
    data = dict(build_root='/', storage_roots=list(map(str, args.root)), depth=args.depth, stage_file_depth=args.depth,
                stage_directories=directories, errors=errors, skipped_links=sorted(set(skipped)), indexes=indexes,
                published=published, staged=rows)
    (args.output / 'inventory.json').write_text(json.dumps(data, indent=2) + '\n')
    (args.output / 'search-errors.txt').write_text('\n'.join(errors) + '\n')
    (args.output / 'skipped-links.txt').write_text('\n'.join(sorted(set(skipped))) + '\n')
    (args.output / 'stage-directories.txt').write_text('\n'.join(directories) + '\n')
    print(json.dumps(dict(stage_directories=len(directories), artifacts=len(rows), published_records=len(published), errors=len(errors), skipped_links=len(set(skipped)))))


if __name__ == '__main__':
    main()
