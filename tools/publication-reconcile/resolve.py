#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Turn a reviewed root/source target map into a version reconciliation table."""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path

from reconcile import newest, compare, write_tsv


def norm(version):
    return version.removesuffix('+lc1')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('inventory', type=Path)
    ap.add_argument('roots', type=Path)
    ap.add_argument('reviewed', type=Path)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    inventory = json.loads(args.inventory.read_text())
    roots = list(csv.DictReader(args.roots.open(), delimiter='\t'))
    reviewed = json.loads(args.reviewed.read_text())
    published, staged, paths = defaultdict(set), defaultdict(set), defaultdict(list)
    for r in inventory['published']:
        published[r['source']].add(norm(r['source_version']))
    for r in inventory['staged']:
        if 'source' in r:
            staged[r['source']].add(norm(r['source_version']))
            paths[(r['source'], norm(r['source_version']))].append(r['path'])
    all_targets = defaultdict(set)
    for record in reviewed.values():
        for target in record['targets']:
            if target.get('version'):
                all_targets[target['source']].add(norm(target['version']))
    rows = []
    for r in roots:
        record = reviewed[r['root']]
        targets = record['targets'] or [{'source': 'no fixed source', 'version': None, 'location': r['root']}]
        for target in targets:
            source, version = target['source'], target.get('version')
            p, s = newest(published[source]), newest(staged[source])
            if not version:
                state = record['mode']
            else:
                version = norm(version)
                current = newest(all_targets[source])
                if compare(version, current) < 0:
                    state = 'retained producer; newer tracked successor'
                elif p != 'absent' and compare(version, p) <= 0:
                    state = 'published or newer published successor'
                elif s != 'absent' and compare(version, s) <= 0:
                    state = 'staged; acceptance/qualification separate'
                else:
                    state = 'recipe newer than published and bounded stages'
            rows.append({'root': r['root'], 'source': source, 'recipe_version': version or 'caller supplied / no fixed version',
                         'published': p, 'newest_staged': s, 'state': state,
                         'location': target['location'], 'note': record['note'],
                         'staged_paths': '; '.join(sorted(set(paths[(source, s)])))})
    fields = ['root', 'source', 'recipe_version', 'published', 'newest_staged', 'state', 'location', 'note', 'staged_paths']
    write_tsv(args.output / 'recipe-reconciliation.tsv', rows, fields)
    text = ['# Reviewed recipe reconciliation', '',
            'Terminal +lc1 marks are normalized only for source-recipe version comparisons. Raw versions remain in the file inventory.', '',
            '| Recipe root | Source | Recipe version | Published | Newest staged | State | Evidence / note |',
            '| --- | --- | --- | --- | --- | --- | --- |']
    for r in rows:
        text.append('| ' + ' | '.join(str(r[k]).replace('|', '\\|') for k in
                    ('root', 'source', 'recipe_version', 'published', 'newest_staged', 'state')) +
                    ' | ' + r['location'] + '; ' + r['note'].replace('|', '\\|') + ' |')
    (args.output / 'recipe-reconciliation.md').write_text('\n'.join(text) + '\n')
    print(f'{len(roots)} tracked roots resolved into {len(rows)} rows')
    for r in rows:
        if r['state'].startswith('recipe newer'):
            print(r['source'], r['recipe_version'], r['location'])


if __name__ == '__main__':
    main()
