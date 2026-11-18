#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Expand explicit stage decisions to source components and build receipts, read-only."""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path
from inventory import paragraphs, walk
from reconcile import write_tsv

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('files', type=Path)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--qualified-artifacts', type=Path, required=True,
                help='exact source-artifacts.tsv emitted by the successful metadata qualification')
a = ap.parse_args()
rows = list(csv.DictReader(a.files.open(), delimiter='\t'))
by_path = {Path(r['stage']) / r['filename']: r for r in rows}
by_source = defaultdict(list)
for r in rows:
    by_source[(r['source'], r['source_version'])].append(r)
expanded, errors = dict(by_path), []

def add(path, owner, kind, declared_sha=''):
    if path in expanded:
        return
    if not path.is_file() or path.is_symlink():
        errors.append(f'missing/nonregular {kind}: {path}')
        return
    expanded[path] = dict(owner, stage=str(path.parent), filename=path.name, kind=kind,
                          binary='', version='', architecture='', bytes=path.stat().st_size,
                          sha256=declared_sha)

for path, r in by_path.items():
    if r['kind'] != 'source':
        continue
    try:
        control = next(p for p in paragraphs(path.read_text()) if 'Source' in p and 'Version' in p)
        for line in control.get('Checksums-Sha256', '').splitlines():
            if not line.strip():
                continue
            sha, size, name = line.split()
            if Path(name).name != name or name in ('.', '..'):
                raise ValueError('unsafe source component ' + name)
            add(path.parent / name, r, 'source-component', sha)
    except (OSError, ValueError, StopIteration) as exc:
        errors.append(str(path) + ': ' + str(exc))

# Receipts may be in sibling architecture/records folders. Search only the supplied
# stage roots to a bounded depth; never inspect arbitrary JSON or evaluate producers.
roots = sorted({Path(r['stage']) for r in rows})
roots = [p for p in roots if not any(p != q and p.is_relative_to(q) for q in roots)]
for root in roots:
    for path in (base / name for base, _, names, _ in walk(root, 3, errors) for name in names):
        if len(path.relative_to(root).parts) > 4 or not path.is_file() or path.is_symlink():
            continue
        if not (path.name.endswith('.sparky-build.json') or path.suffix in ('.buildinfo', '.changes')):
            continue
        try:
            if path.stat().st_size > 4 * 1024**2:
                raise ValueError('oversized receipt')
            if path.name.endswith('.sparky-build.json'):
                c = json.loads(path.read_text()); key = (c.get('source'), c.get('version'))
                kind = 'build-record'
            else:
                c = next(p for p in paragraphs(path.read_text()) if 'Source' in p and 'Version' in p)
                key = (c['Source'].split()[0], c['Version']); kind = path.suffix[1:]
            choices = by_source[key]
            if not choices:
                errors.append(f'unmatched receipt identity {key}: {path}')
                continue
            # Pick the longest common stage ancestry, never a newer source version.
            def proximity(r):
                left, right = path.parts, Path(r['stage']).parts
                n = 0
                for x, y in zip(left, right):
                    if x != y:
                        break
                    n += 1
                return n
            best = max(map(proximity, choices))
            choices = [r for r in choices if proximity(r) == best]
            decisions = {r['decision'] for r in choices}
            if len(decisions) > 1:
                # A matching descriptor controls its own source receipts. Where no
                # descriptor disambiguates, retain an explicit review disposition.
                descriptors = [r for r in choices if r['kind'] == 'source']
                if descriptors and len({r['decision'] for r in descriptors}) == 1:
                    owner = descriptors[0]
                else:
                    owner = dict(choices[0], decision='review-receipt', reason='Mixed input dispositions; no unique descriptor authority for receipt')
            else:
                owner = choices[0]
            add(path, owner, kind)
        except (OSError, ValueError, StopIteration) as exc:
            errors.append(str(path) + ': ' + str(exc))

# Only the independently qualified artifact paths can grant a candidate decision.
# A receipt with the same source/version in another stage is not interchangeable.
qualified = {Path(r['path']): r for r in csv.DictReader(a.qualified_artifacts.open(), delimiter='\t')}
for path, r in expanded.items():
    if r['decision'] == 'candidate' and path not in qualified:
        r['decision'] = 'unselected-receipt'
        r['reason'] = 'Not an artifact of the exact qualified source closure; matching source/version alone does not select another stage receipt'
for path, r in qualified.items():
    if not path.is_file():
        raise ValueError('qualified artifact disappeared: ' + str(path))
    if path not in expanded:
        kind = ('build-record' if path.name.endswith('.sparky-build.json') else
                'buildinfo' if path.suffix == '.buildinfo' else 'changes' if path.suffix == '.changes' else 'source-component')
        expanded[path] = dict(stage=str(path.parent), filename=path.name, kind=kind,
                              source=r['source'], source_version=r['version'], binary='', version='', architecture='', variant='')
    expanded[path].update(decision='candidate', reason='Exact independently qualified source closure artifact',
                          sha256=r['sha256'], bytes=r['bytes'])

fields = ['stage', 'filename', 'kind', 'source', 'source_version', 'binary', 'version',
          'architecture', 'variant', 'decision', 'reason', 'bytes', 'sha256']
a.output.mkdir(parents=True, exist_ok=True)
write_tsv(a.output / 'stage-closure-decisions.tsv', [expanded[p] for p in sorted(expanded)], fields)
write_tsv(a.output / 'leave-out-list.tsv', [expanded[p] for p in sorted(expanded)
                                          if expanded[p]['decision'] != 'candidate'], fields)
(a.output / 'leave-out-expansion-errors.txt').write_text('\n'.join(errors) + ('\n' if errors else ''))
print(f'{len(expanded)} artifacts, {sum(r["decision"] != "candidate" for r in expanded.values())} excluded, {len(errors)} discovery limitations')
