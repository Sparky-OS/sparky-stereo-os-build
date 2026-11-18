#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Reconcile a read-only inventory with an explicit source-generation allowlist.

This is a discovery report, not a qualification or publication command.
"""
import argparse
from collections import Counter, defaultdict
import csv
from functools import lru_cache
import json
from pathlib import Path
import re
import subprocess

from inventory import digest


@lru_cache(maxsize=None)
def compare(a, b):
    for relation, result in [('lt', -1), ('eq', 0), ('gt', 1)]:
        if subprocess.run(['dpkg', '--compare-versions', a, relation, b], check=False).returncode == 0:
            return result
    raise ValueError(f'invalid Debian version: {a!r} or {b!r}')


def newest(versions):
    answer = None
    for version in versions:
        if answer is None or compare(version, answer) > 0:
            answer = version
    return answer or 'absent'


def write_tsv(path, rows, fields):
    with path.open('w') as stream:
        writer = csv.DictWriter(stream, fields, delimiter='\t', extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)


def binary_key(row):
    return tuple(row.get(k, '') for k in ('binary', 'version', 'architecture', 'variant'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory', type=Path)
    parser.add_argument('allowlist', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.inventory.read_text())
    rules = json.loads(args.allowlist.read_text())
    published, published_versions = {}, defaultdict(set)
    for row in data['published']:
        published_versions[row['source']].add(row['source_version'])
        if row['kind'] == 'binary':
            published[binary_key(row)] = row
    accepted = {(r['source'], r['version']) for r in rules
                if r['decision'] == 'candidate' and r.get('source') and r.get('version')}
    groups, files = defaultdict(list), []
    for row in data['staged']:
        if 'error' in row:
            continue
        path = Path(row['path'])
        source, version = row['source'], row['source_version']
        baseline = newest(published_versions[source])
        decision, reason = 'unlisted', 'No accepted source generation at this path in the brief'
        for rule in rules:
            root = Path(rule['root'])
            if path.is_relative_to(root) and (rule.get('source') in (None, source)) \
                    and (rule.get('version') in (None, version)):
                decision, reason = rule['decision'], rule['reason']
                break
        if decision == 'unlisted' and any(p in ('superseded', 'predecessor') for p in path.parts):
            decision, reason = 'superseded', 'Excluded predecessor/superseded folder; no explicit exception'
        if decision == 'unlisted':
            for accepted_source, accepted_version in sorted(accepted):
                if source == accepted_source and compare(version, accepted_version) < 0:
                    decision, reason = 'superseded', f'Older than accepted {source} {accepted_version}'
                    break
        if decision == 'candidate' and baseline != 'absent' and compare(version, baseline) <= 0:
            decision, reason = 'already-published-version', 'Accepted path is not newer than published source; inspect binary identity'
        published_binary = published.get(binary_key(row)) if row['kind'] == 'binary' else None
        byte_check = 'not-compared'
        if published_binary:
            sha = digest(path)
            row['sha256'] = sha
            byte_check = 'equal' if sha == published_binary['sha256'] else 'DIFFERENT'
            if byte_check == 'equal' and decision not in ('held', 'superseded'):
                decision, reason = 'already-published', 'Exact published binary identity and SHA-256'
            elif byte_check == 'DIFFERENT':
                reason += '; same published binary identity has DIFFERENT bytes (cannot replace in place)'
                if decision in ('candidate', 'already-published-version'):
                    decision = 'identity-conflict'
        record = dict(row, stage=str(path.parent), filename=path.name,
                      published=baseline, decision=decision, reason=reason, published_bytes=byte_check)
        files.append(record)
        groups[(str(path.parent), source, version, decision, reason)].append(record)
    args.output.mkdir(parents=True, exist_ok=True)
    fields = ['stage', 'filename', 'kind', 'source', 'source_version', 'binary', 'version',
              'architecture', 'variant', 'lean', 'published', 'decision', 'reason', 'published_bytes', 'bytes', 'sha256']
    write_tsv(args.output / 'stage-files.tsv', files, fields)
    write_tsv(args.output / 'candidate-binaries.tsv',
              [r for r in files if r['kind'] == 'binary' and r['decision'] == 'candidate'], fields)
    write_tsv(args.output / 'leave-out-binaries.tsv',
              [r for r in files if r['kind'] == 'binary' and r['decision'] != 'candidate'], fields)
    summary = []
    for (stage, source, version, decision, reason), rows in sorted(groups.items()):
        summary.append(dict(stage=stage, source=source, version=version, published=rows[0]['published'],
                            decision=decision, binaries=sum(r['kind'] == 'binary' for r in rows),
                            descriptors=sum(r['kind'] == 'source' for r in rows), reason=reason))
    write_tsv(args.output / 'stage-sources.tsv', summary,
              ['stage', 'source', 'version', 'published', 'decision', 'binaries', 'descriptors', 'reason'])
    lines = ['# Staged source generations', '',
             'Candidates below are accepted generations awaiting metadata, payload and release qualification.', '',
             '| Stage folder | Source | Source version | Published | Binaries / dsc | Decision | Reason |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    for row in summary:
        lines.append('| ' + ' | '.join(str(row[k]).replace('|', '\\|') for k in
                     ('stage', 'source', 'version', 'published')) +
                     f" | {row['binaries']} / {row['descriptors']} | {row['decision']} | {row['reason']} |")
    (args.output / 'stage-sources.md').write_text('\n'.join(lines) + '\n')
    orders = defaultdict(list)
    for row in files:
        if row['published_bytes'] == 'equal':
            folder = Path(row['path']).relative_to(data.get('build_root', '/mnt/build')).parts[0]
            match = re.search(r'-(\d+[a-z]?)$', folder)
            orders[(match[1] if match else 'no ORDER suffix', folder)].append(row)
    text = ['# Already published staged binaries', '',
            'Every row here matches the published binary identity and SHA-256; not an acceptance of the whole lane.', '',
            '| ORDER | Folder | Binary files | Sources |', '| --- | --- | --- | --- |']
    for (order, folder), rows in sorted(orders.items()):
        text.append(f"| {order} | {folder} | {len(rows)} | " + ', '.join(sorted({r['source'] for r in rows})) + ' |')
    (args.output / 'already-published-by-order.md').write_text('\n'.join(text) + '\n')
    counts = Counter(r['decision'] for r in files if r['kind'] == 'binary')
    counts['published_byte_equal'] = sum(r['published_bytes'] == 'equal' for r in files)
    counts['published_identity_different_bytes'] = sum(r['published_bytes'] == 'DIFFERENT' for r in files)
    counts['candidate_binary_bytes'] = sum(r['bytes'] for r in files if r['kind'] == 'binary' and r['decision'] == 'candidate')
    (args.output / 'decision-counts.json').write_text(json.dumps(counts, indent=2) + '\n')
    print(json.dumps(counts))


if __name__ == '__main__':
    main()
