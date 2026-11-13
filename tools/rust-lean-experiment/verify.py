#!/usr/bin/env python3
"""Independently check prepared source manifests and emit tree census tables.

These totals describe source files, not the files a build actually consumed.
"""
from collections import Counter
import argparse
import hashlib
import json
import os
from pathlib import Path


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify_tree(root, manifest):
    actual = {}
    for p in root.rglob('*'):
        if p.is_symlink():
            row = {'path': p.relative_to(root).as_posix(), 'link': os.readlink(p)}
        elif p.is_file():
            raw = p.read_bytes()
            row = {'path': p.relative_to(root).as_posix(), 'mode': p.stat().st_mode & 0o7777,
                   'bytes': len(raw), 'sha256': digest(raw)}
        else:
            continue
        actual[row['path']] = row
    expected = {r['path']: r for r in manifest['files']}
    if actual != expected:
        changed = sorted(n for n in actual.keys() | expected.keys() if actual.get(n) != expected.get(n))
        raise ValueError(f'{root}: changed, missing or extra files: {changed[:5]}')
    canonical = json.dumps(sorted(actual.values(), key=lambda r: r['path']),
                           sort_keys=True, separators=(',', ':')).encode()
    if digest(canonical) != manifest['sha256']:
        raise ValueError(f'{root}: manifest digest disagrees')
    return actual


def verify(authored, forms):
    report = json.loads((forms / 'source-report.json').read_text())
    if report['version'] != 'order541-source-v1' or report['build_qualified'] is not False:
        raise ValueError('unknown preparation version or premature build-qualification claim')
    maps, roots = {}, {'A': authored, 'B': forms / 'B', 'C': forms / 'C'}
    for f, root in roots.items():
        manifest = json.loads((forms / (f + '-manifest.json')).read_text())
        if manifest['sha256'] != report['forms'][f]['sha256']:
            raise ValueError(f'{f}: report and manifest disagree')
        maps[f] = verify_tree(root, manifest)
    permitted = {f: {r['path'] for r in report['forms'][f]['cargo_checksums_updated']}
                 for f in ('B', 'C')}
    for f in ('B', 'C'):
        for name in maps['A'].keys() | maps[f].keys():
            a, b = maps['A'].get(name), maps[f].get(name)
            if a != b and name not in report['files'] and name not in permitted[f]:
                raise ValueError(f'{f}: unrecorded change to {name}')
        for name, row in report['files'].items():
            a, b = maps['A'][name], maps[f][name]
            if 'left' in row:
                if a != b:
                    raise ValueError(f'{f}: preserved source changed: {name}')
            elif row['sha256_A'] != a['sha256'] or row['sha256_' + f] != b['sha256']:
                raise ValueError(f'{f}: lexer evidence and source disagree: {name}')
    totals, groups = {}, {}
    for f, root in roots.items():
        totals[f] = Counter(files=0, bytes=0, lines=0)
        groups[f] = {}
        for name in report['files']:
            raw = (root / name).read_bytes()
            values = Counter(files=1, bytes=len(raw), lines=raw.count(b'\n'))
            totals[f].update(values)
            groups[f].setdefault(name.split('/')[0], Counter()).update(values)
    result = {'kind': 'source-tree census, not actual compiler reads', 'totals': totals, 'groups': groups,
              'lexer_checked_files': sum('left' not in r for r in report['files'].values()),
              'preserved_files': sum('left' in r for r in report['files'].values()),
              'changed_files': report['changed'], 'C_doc_exception_crates': len(report['C_doc_exceptions']),
              'tree_checksums': {f: report['forms'][f]['sha256'] for f in roots}}
    text = ['# Prepared source census', '', result['kind'], '',
            '| Form | Rust files | Bytes | Lines | Changed files |', '| --- | ---: | ---: | ---: | ---: |']
    for f in roots:
        t = totals[f]
        text.append(f'| {f} | {t["files"]} | {t["bytes"]} | {t["lines"]} | {report["changed"].get(f, 0)} |')
    for suffix, raw in [('json', json.dumps(result, indent=2, sort_keys=True) + '\n'),
                        ('md', '\n'.join(text) + '\n')]:
        path = forms / ('census.' + suffix)
        tmp = path.with_suffix(path.suffix + '.partial')
        tmp.write_text(raw)
        tmp.replace(path)
    print('\n'.join(text))
    print('PASS: complete file/mode/link manifests, ledger and preservation checks')


if __name__ == '__main__':
    os.environ['LC_ALL'] = 'C'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('authored', type=Path)
    parser.add_argument('forms', type=Path)
    args = parser.parse_args()
    verify(args.authored, args.forms)
