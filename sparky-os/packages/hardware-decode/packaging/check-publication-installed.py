#!/usr/bin/env python3
"""Verify the copy-installed cohort and run its predecessor link gate."""
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
import csv
import hashlib
import json
from pathlib import Path
import subprocess

expected = json.loads(Path('/w/a10-runtime-packages.json').read_text())['after']
actual = {}
for package, version in expected.items():
    actual[package] = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', package], text=True)
    assert actual[package] == version, (package, version, actual[package])
Path('/w/runtime-versions-verified.json').write_text(json.dumps(actual, indent=2, sort_keys=True)+'\n')
check = subprocess.run(['dpkg', '--verify', *expected], capture_output=True, text=True)
Path('/w/dpkg-verify.log').write_text(check.stdout+check.stderr)
assert check.returncode == 0 and not check.stdout and not check.stderr, 'installed payload differs from its package'
archives = []
for row in csv.DictReader(Path('/w/cohort.tsv').open(), delimiter='\t'):
    if row['architecture'] not in ('amd64', 'all') or any(s in row['package'] for s in ('-dbgsym', '-lc-hr')):
        continue
    source, filename = Path(row['path']).parts[1:]
    matches = list(Path('/pub/pool/main').glob('*/'+source+'/'+filename))
    assert len(matches) == 1, (source, filename)
    archive = matches[0]
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == row['sha256'], archive
    archives.append(str(archive))
subprocess.run(['python3', '-m', 'lean.release', 'check-link', '--previous-dir', '/previous', *archives], check=True)
print(f'PASS: {len(actual)} installed runtime versions and payloads, plus the copy archive predecessor link gate')
