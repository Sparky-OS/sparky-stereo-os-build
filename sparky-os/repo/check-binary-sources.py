#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Refuse a repository whose indexed binaries lack indexed, complete sources."""
import argparse
import bz2
import csv
import gzip
import hashlib
import lzma
from pathlib import Path
import re
import sys


def paragraphs(text):
    row, field = {}, None
    for line in text.splitlines() + ['']:
        if not line.strip():
            if row:
                yield row
            row, field = {}, None
        elif line[0].isspace():
            if field is None:
                raise ValueError('continuation without a field')
            row[field] += '\n' + line[1:]
        else:
            field, sep, value = line.partition(':')
            field = field.lower()
            if not sep or field in row:
                raise ValueError('malformed or duplicate field: ' + line)
            row[field] = value.strip()


def read(path):
    opener = {'.xz': lzma.open, '.gz': gzip.open, '.bz2': bz2.open}.get(path.suffix, open)
    with opener(path, 'rt', encoding='utf-8') as stream:
        return stream.read()


def indexes(root, kind):
    groups = {}
    for path in sorted((root / 'dists').rglob(kind + '*')):
        if path.name not in (kind, kind + '.xz', kind + '.gz', kind + '.bz2'):
            continue
        if kind == 'Packages' and not path.parent.name.startswith('binary-'):
            continue
        if kind == 'Sources' and path.parent.name != 'source':
            continue
        groups.setdefault(path.parent, []).append(path)
    if not groups:
        raise ValueError('no ' + kind + ' indexes')
    for parent, paths in sorted(groups.items()):
        path = min(paths, key=lambda p: (p.name != kind, p.name))
        yield path, list(paragraphs(read(path)))


def inside(root, relative):
    path = root / relative
    if Path(relative).is_absolute() or '..' in Path(relative).parts:
        raise ValueError('unsafe archive path: ' + relative)
    return path


def descriptor_problem(root, source):
    name, version = source['package'], source['version']
    checks = [line.split() for line in source['checksums-sha256'].splitlines() if line.strip()]
    descriptors = [r for r in checks if r[2].endswith('.dsc')]
    if len(descriptors) != 1:
        return 'Sources must name exactly one .dsc'
    digest, size, filename = descriptors[0]
    path = inside(root, source['directory'] + '/' + filename)
    if not path.is_file():
        return 'missing .dsc: ' + str(path.relative_to(root))
    data = path.read_bytes()
    if len(data) != int(size) or hashlib.sha256(data).hexdigest() != digest:
        return '.dsc differs from Sources: ' + str(path.relative_to(root))
    text = data.decode('utf-8')
    if text.startswith('-----BEGIN PGP SIGNED MESSAGE-----'):
        text = text.split('\n\n', 1)[1].split('\n-----BEGIN PGP SIGNATURE-----', 1)[0]
        text = '\n'.join(line[2:] if line.startswith('- ') else line for line in text.splitlines())
    fields = list(paragraphs(text))
    if len(fields) != 1 or fields[0].get('source') != name or fields[0].get('version') != version:
        return '.dsc identity differs from Sources: ' + filename
    closure = [r.split() for r in fields[0]['checksums-sha256'].splitlines() if r.strip()]
    if not closure:
        return 'empty .dsc source closure: ' + filename
    indexed = {r[2]: r[:2] for r in checks}
    for sha, length, component in closure:
        if indexed.get(component) != [sha, length]:
            return '.dsc component differs from Sources: ' + component
        archive = inside(root, source['directory'] + '/' + component)
        if not archive.is_file() or archive.stat().st_size != int(length):
            return 'missing or wrong-sized source component: ' + str(archive.relative_to(root))
    return None


def audit(root):
    sources = {}
    for index, records in indexes(root, 'Sources'):
        suite = index.relative_to(root / 'dists').parts[0]
        for row in records:
            key = suite, row['package'], row['version']
            problem = descriptor_problem(root, row)
            sources.setdefault(key, []).append(problem)
    rows = set()
    for index, records in indexes(root, 'Packages'):
        suite = index.relative_to(root / 'dists').parts[0]
        for binary in records:
            source = binary.get('source', binary['package'])
            match = re.fullmatch(r'([a-z0-9][a-z0-9+.-]*)(?:\s+\(([^()\s]+)\))?', source)
            if not match:
                raise ValueError('malformed Source: ' + source)
            name, version = match[1], match[2] or binary['version']
            key = suite, name, version
            candidates = sources.get(key)
            problem = ('missing from Sources' if candidates is None else
                       '; '.join(sorted(set(p for p in candidates if p))) if all(candidates) else '')
            rows.add((suite, binary['package'], binary['version'], binary['architecture'],
                      name, version, 'missing' if problem else 'present', problem))
    if not rows:
        raise ValueError('binary indexes contain zero packages')
    return sorted(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tree', type=Path)
    parser.add_argument('--table', type=Path, help='write every binary/source pair as TSV')
    args = parser.parse_args()
    try:
        rows = audit(args.tree.resolve())
        if args.table:
            with args.table.open('w') as stream:
                writer = csv.writer(stream, delimiter='\t')
                writer.writerow(['suite', 'package', 'binary_version', 'architecture',
                                 'source', 'source_version', 'status', 'reason'])
                writer.writerows(rows)
        missing = [r for r in rows if r[6] == 'missing']
        for r in missing:
            print(f'MISSING {r[1]} {r[2]} {r[3]}: Source {r[4]} ({r[5]}); {r[7]}')
        print(f'{len(rows)} binaries checked; {len(missing)} missing; '
              f'{len(set((r[4], r[5]) for r in missing))} missing source versions')
        return int(bool(missing))
    except (OSError, ValueError, KeyError, IndexError, EOFError) as error:
        print('source gate could not check: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
