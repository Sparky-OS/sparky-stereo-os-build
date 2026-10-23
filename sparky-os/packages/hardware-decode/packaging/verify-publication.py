#!/usr/bin/env python3
"""Check the cohort's pool delta and the complete published index closure."""
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('baseline', type=Path)
p.add_argument('candidate', type=Path)
a = p.parse_args()
allowed = set(json.loads(Path(__file__).with_name('versions.json').read_text()))

def files(root):
    return {str(f.relative_to(root)): f for f in (root/'pool').rglob('*') if f.is_file()}

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

old, new = files(a.baseline), files(a.candidate)
added, removed = sorted(new.keys()-old.keys()), sorted(old.keys()-new.keys())
changed = [name for name in sorted(old.keys() & new.keys()) if digest(old[name]) != digest(new[name])]
assert not changed, ('immutable pool paths changed', changed)
for name in added+removed:
    assert Path(name).parts[3] in allowed, ('unrelated pool delta', name)
assert {Path(name).parts[3] for name in added} == allowed, 'a cohort source family is absent'

# The Debian indexes must account for every pool file, including source closure.
def stanzas(path):
    for paragraph in path.read_text().split('\n\n'):
        result = {}
        key = None
        for line in paragraph.splitlines():
            if line.startswith((' ', '\t')):
                if key: result[key] += '\n'+line.strip()
            elif ': ' in line or line.endswith(':'):
                key, value = line.split(':', 1)
                result[key] = value.strip()
        if result: yield result

referenced = set()
cache = {}
def check(relative, size, sha256):
    assert relative in new, ('index refers to absent pool file', relative)
    path = new[relative]
    assert path.stat().st_size == int(size), relative
    if relative not in cache: cache[relative] = digest(path)
    assert cache[relative] == sha256, ('index hash mismatch', relative)
    referenced.add(relative)

root = a.candidate/'dists/mashtabba/main'
for index in sorted(root.glob('binary-*/Packages')):
    for row in stanzas(index):
        check(row['Filename'], row['Size'], row['SHA256'])
for row in stanzas(root/'source/Sources'):
    for line in row['Checksums-Sha256'].splitlines():
        if not line: continue
        sha256, size, name = line.split()
        check(row['Directory']+'/'+name, size, sha256)
assert referenced == new.keys(), ('unindexed pool files', sorted(new.keys()-referenced))
print(json.dumps({'added': added, 'removed': removed, 'same_name_changed': changed,
                  'pool_files': len(new), 'index_references': len(referenced),
                  'changed_sources': sorted(allowed)}, indent=2))
