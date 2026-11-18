#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare every selected binary with its published counterpart, one source family at a time."""
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess

TAG_LINE = re.compile(r'^([EWIPXO]): ([^:]+): ([a-z0-9][a-z0-9+.-]*)(?: (.*))?$')

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('files', type=Path)
ap.add_argument('inventory', type=Path)
ap.add_argument('--pool', type=Path, required=True)
ap.add_argument('--published', type=Path, required=True)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--resume', action='store_true', help='reuse only complete paired families in this frozen pool')
ap.add_argument('--frozen-pool-id', help='expected SHA-256 of pool/SHA256SUMS; required for resume')
a = ap.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
completed = {}
if a.resume:
    if not a.frozen_pool_id or hashlib.sha256((a.pool/'SHA256SUMS').read_bytes()).hexdigest() != a.frozen_pool_id:
        raise ValueError('resume requires the exact declared frozen pool identity')
    completed = {r['source']:r for r in json.loads((a.output/'progress.json').read_text())}
rows = [r for r in csv.DictReader(a.files.open(), delimiter='\t')
        if r['kind'] == 'binary' and r['decision'] == 'candidate']
old = {(r['binary'], r['architecture'], r.get('variant', '')): r
       for r in json.loads(a.inventory.read_text())['published'] if r['kind'] == 'binary'}
groups = defaultdict(list)
for r in rows:
    groups[r['source']].append(r)
results, tags = [], {'current': Counter(), 'published': Counter()}
for source in sorted(groups, key=lambda s: sum((a.pool/r['filename']).stat().st_size for r in groups[s])):
    selected = groups[source]
    previous = [old[k] for r in selected if (k := (r['binary'], r['architecture'], r.get('variant', ''))) in old]
    versions = sorted({r['version'] for r in selected + previous}, key=len, reverse=True)
    result = {'source': source, 'current_binaries': len(selected), 'published_binaries': len(previous)}
    saved = completed.get(source)
    if saved:
        assert all(saved[k] == result[k] for k in result), source
    for side, paths in [('current', [a.pool/r['filename'] for r in selected]),
                        ('published', [a.published/r['filename'] for r in previous])]:
        log = a.output/(source+'-'+side+'.log')
        if saved:
            assert log.is_file(), log
            result[side+'_rc'] = saved[side+'_rc']
        else:
            with log.open('w') as stream:
                run = subprocess.run(['lintian', '--allow-root', '--tag-display-limit', '0', *map(str, paths)],
                                     stdout=stream, stderr=subprocess.STDOUT) if paths else None
            result[side+'_rc'] = run.returncode if run else None
        tag_count, other = 0, []
        for line in log.read_text(errors='replace').splitlines():
            match = TAG_LINE.match(line)
            if match:
                level, package, tag, context = match.groups()
                context = context or ''
                for version in versions:
                    context = context.replace(version, '<VERSION>')
                tags[side][(source, package, level, tag, context)] += 1
                tag_count += 1
            elif line.strip():
                other.append(line)
        result[side+'_tag_lines'] = tag_count
        result[side+'_other_lines'] = other
        if saved:
            # A corrected parser may recognize a formerly retained diagnostic
            # as a tag. Account for each reclassification explicitly.
            prior_other = saved[side+'_other_lines']
            reclassified = sum(bool(TAG_LINE.match(line)) for line in prior_other)
            assert tag_count == saved[side+'_tag_lines'] + reclassified, log
            assert other == [line for line in prior_other if not TAG_LINE.match(line)], log
        result[side+'_log_sha256'] = hashlib.sha256(log.read_bytes()).hexdigest()
        if saved and side+'_log_sha256' in saved:
            assert result[side+'_log_sha256'] == saved[side+'_log_sha256'], log
    results.append(result)
    (a.output/'progress.json').write_text(json.dumps(results, indent=2)+'\n')
    print(source, result, flush=True)
keys = sorted(set(tags['current']) | set(tags['published']))
with (a.output/'delta.tsv').open('w') as stream:
    writer = csv.writer(stream, delimiter='\t')
    writer.writerow(['source','binary','level','tag','context_version_normalized','published','current','delta'])
    for key in keys:
        before, after = tags['published'][key], tags['current'][key]
        if before != after:
            writer.writerow([*key, before, after, after-before])
summary = {'source_families': len(results), 'current_binaries': sum(r['current_binaries'] for r in results),
           'published_binaries': sum(r['published_binaries'] for r in results),
           'current_tag_lines': sum(tags['current'].values()), 'published_tag_lines': sum(tags['published'].values()),
           'changed_tag_contexts': sum(tags['current'][k] != tags['published'][k] for k in keys),
           'family_results': results}
assert summary['current_binaries'] == len(rows)
(a.output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print('Completed paired lintian coverage:', summary['current_binaries'], summary['published_binaries'], flush=True)
