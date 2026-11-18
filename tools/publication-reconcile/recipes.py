#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Catalogue tracked recipe roots and version evidence without running producers.

Dynamic expressions are retained for human resolution, never evaluated.
A literal candidate is evidence, not a declaration that a historical producer
is authoritative. Resolve root/source mappings before using this as a build list.
"""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path
import re
import subprocess

from reconcile import newest, compare, write_tsv


PATTERN = re.compile(
    r'''(?:\b(?:VERSION|NEW_VERSION|NEXT|VER|NEWV|NEW|V|version|edition_version)\s*=\s*["']?(?:\$\{[A-Z_]+:-)?|--(?:next|newversion)["']?[,\s]+["']?)([0-9][0-9A-Za-z.+:~_-]*)''')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--inventory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    tracked = subprocess.check_output(['git', '-C', str(args.build), 'ls-files', '-z'], text=True).split('\0')
    data = json.loads(args.inventory.read_text())
    known = {r['source'] for r in data['published'] + data['staged'] if 'source' in r}
    published, staged = defaultdict(set), defaultdict(set)
    for r in data['published']:
        published[r['source']].add(r['source_version'])
    for r in data['staged']:
        if 'source' in r:
            staged[r['source']].add(r['source_version'])
    roots = defaultdict(list)
    for rel in tracked:
        parts = Path(rel).parts
        if len(parts) > 3 and parts[:2] in (('sparky-os', 'packages'), ('sparky-os', 'upstream')):
            roots['/'.join(parts[:3])].append(rel)
    records, expressions = [], []
    for root, paths in sorted(roots.items()):
        name = Path(root).name
        producers, evidence, dynamic = [], [], []
        source_names = set()
        if name in known:
            source_names.add(name)
        for rel in paths:
            path = args.build / rel
            if not path.is_file() or path.stat().st_size > 1024 * 1024:
                continue
            suffix = path.suffix
            if suffix not in ('.sh', '.py', '.env', '.json', '.txt', ''):
                continue
            if any(p in ('tests', 'autotests', 'fixtures', 'upstream', 'vendor') for p in Path(rel).parts[3:]):
                continue
            text = path.read_text(errors='replace')
            producer = suffix in ('.sh', '.py') and re.search(r'dpkg-(?:source|buildpackage)|lean\.standalone|lc-successor\.py|debian_prepare', text)
            if producer:
                producers.append(rel)
            if path.name == 'control' and path.parent.name == 'debian':
                match = re.search(r'^Source:\s*(\S+)', text, re.M)
                if match:
                    source_names.add(match[1])
            if not producer and path.name not in ('CHANGELOG', 'changelog') and suffix not in ('.env', '.json') and 'changelog' not in str(path).lower() and 'changelog' not in text:
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if line.lstrip().startswith('#'):
                    continue
                assignment = re.match(r'^(?:export )?(?:VERSION|NEW_VERSION|NEXT|VER|NEWV|NEW|V|version|edition_version)\s*=', line.strip())
                target_flag = re.search(r'--(?:next|newversion)', line)
                for match in PATTERN.finditer(line) if assignment or target_flag else []:
                    v = match[1]
                    if v.isdigit() and len(v) < 8:
                        continue
                    evidence.append((v, f'{rel}:{n}', line.strip()))
                if re.search(r'\b(?:VERSION|NEW_VERSION|NEXT|VER|NEWV|NEW|V|version|edition_version)\s*=|--next |--newversion', line):
                    dynamic.append(f'{rel}:{n}: {line.strip()}')
            for match in re.finditer(r'([a-z][a-z0-9.+-]+) \(([0-9][^ )]+)\) (?:unstable|mashtabba|UNRELEASED)[^;]*;', text, re.M):
                source_names.add(match[1])
                n = text[:match.start()].count('\n') + 1
                evidence.append((match[2], f'{rel}:{n}', match[0]))
            if path.name == 'changelog' and path.parent.name == 'debian':
                match = re.match(r'([\w.+-]+)\s+\(([^)]+)\)', text)
                if match:
                    source_names.add(match[1])
                    evidence.append((match[2], f'{rel}:1', text.splitlines()[0]))
            elif path.name == 'CHANGELOG':
                match = re.search(r'^\s*Version (\S+)', text, re.M)
                if match:
                    n = text[:match.start()].count('\n') + 1
                    evidence.append((match[1], f'{rel}:{n}', match[0].strip()))
        if name == 'rustc':
            # Each compiler is a distinct required recipe, including the seed.
            for rel in paths:
                if '/versions/' in rel and rel.endswith('.env'):
                    text = (args.build / rel).read_text()
                    env = dict(re.findall(r'^(\w+)=([^\s#]+)', text, re.M))
                    v = env['DEBIAN_VERSION'] + '+' + env['EDITION'] + '+lc1'
                    evidence.append((v, rel, 'DEBIAN_VERSION + EDITION + lc1'))
        for v, line, expression in sorted(set(evidence)):
            expressions.append(dict(root=root, version=v, location=line, expression=expression))
        sources = sorted(source_names)
        record = dict(root=root, tracked_files=len(paths), producers='; '.join(producers),
                      sources='; '.join(sources) or 'unresolved',
                      published='; '.join(f'{s}={newest(published[s])}' for s in sources) or 'unresolved',
                      staged='; '.join(f'{s}={newest(staged[s])}' for s in sources) or 'unresolved',
                      literal_versions='; '.join(sorted({v for v, _, _ in evidence})) or 'none',
                      locations='; '.join(sorted({line for _, line, _ in evidence})),
                      status='needs-authoritative-recipe-resolution' if producers else 'patch-or-input-root',
                      dynamic_expressions='\n'.join(dynamic))
        records.append(record)
    fields = ['root', 'tracked_files', 'producers', 'sources', 'published', 'staged', 'literal_versions', 'locations', 'status', 'dynamic_expressions']
    write_tsv(args.output / 'recipe-roots.tsv', records, fields)
    write_tsv(args.output / 'recipe-version-evidence.tsv', expressions, ['root', 'version', 'location', 'expression'])
    text = ['# Tracked recipe roots', '',
            'Static discovery only. Literal versions include historical producers. Unresolved roots are not unbuilt-package claims.', '',
            '| Root | Files | Source identity | Published | Newest staged | Literal version evidence | State |',
            '| --- | --- | --- | --- | --- | --- | --- |']
    for r in records:
        text.append('| ' + ' | '.join(str(r[k]).replace('|', '\\|') for k in
                    ('root', 'tracked_files', 'sources', 'published', 'staged', 'literal_versions', 'status')) + ' |')
    (args.output / 'recipe-roots.md').write_text('\n'.join(text) + '\n')
    # Missing source checkouts remain explicit, never interpreted as missing recipes.
    gitlinks = subprocess.check_output(['git', '-C', str(args.build), 'ls-files', '--stage'], text=True)
    links = []
    for line in gitlinks.splitlines():
        if line.startswith('160000 '):
            meta, rel = line.split('\t', 1)
            directory = args.build / rel
            links.append(dict(path=rel, commit=meta.split()[1],
                              initialized=(directory / '.git').exists()))
    (args.output / 'source-checkouts.json').write_text(json.dumps(links, indent=2) + '\n')
    print(json.dumps({'recipe_roots': len(records), 'producer_roots': sum(bool(r['producers']) for r in records),
                      'version_evidence': len(expressions), 'gitlinks': len(links),
                      'uninitialized_gitlinks': sum(not r['initialized'] for r in links)}))


if __name__ == '__main__':
    main()
