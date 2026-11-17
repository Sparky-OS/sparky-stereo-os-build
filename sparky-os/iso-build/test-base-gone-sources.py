#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise coverage failures, transport failures and a source returning to unstable."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

check = Path(__file__).with_name('check-base-gone-sources.py')
with tempfile.TemporaryDirectory() as work:
    root = Path(work)
    gone, mapping, snapshot = (root / name for name in ('gone.tsv', 'sources.tsv', 'snapshot.json'))
    gone.write_text('old-binary\treviewed removal\n')
    mapping.write_text('old-binary\told-source\n')
    args = [sys.executable, str(check), '--gone', str(gone), '--sources', str(mapping), '--snapshot', str(snapshot)]
    snapshot.write_text(json.dumps({'responses': {'old-source': {'package': 'old-source', 'versions': []}}}))
    result = subprocess.run(args, capture_output=True, text=True)
    assert result.returncode == 0 and '\tNO\tNO\t-\tNO-SID-SOURCE' in result.stdout, result
    snapshot.write_text(json.dumps({'responses': {'old-source': {'package': 'old-source', 'versions': [{'version': '2-1', 'suites': ['sid']}]}}}))
    result = subprocess.run(args, capture_output=True, text=True)
    assert result.returncode == 0 and '\tYES\tNO\t2-1\tSID-ONLY-REVIEW' in result.stdout, result
    print('GREEN: a returned sid source changes NO to YES and prints SID-ONLY-REVIEW')
    gone.write_text(gone.read_text() + 'unmapped\tnew exclusion\n')
    result = subprocess.run(args, capture_output=True, text=True)
    assert result.returncode == 1 and 'unmapped' in result.stderr, result
    print('RED: a new excluded binary without a source identity fails')
    gone.write_text('old-binary\treviewed removal\n')
    snapshot.write_text(json.dumps({'responses': {}}))
    result = subprocess.run(args, capture_output=True, text=True)
    assert result.returncode == 1 and '\tUNKNOWN\tUNKNOWN\t-\tERROR' in result.stdout, result
    print('RED: a failed lookup prints UNKNOWN and fails rather than reporting absence')
    snapshot.write_text(json.dumps({'responses': {'old-source': {'package': 'wrong-source', 'versions': []}}}))
    result = subprocess.run(args, capture_output=True, text=True)
    assert result.returncode == 1 and 'invalid sources.debian.org response' in result.stderr, result
    print('RED: a mismatched source response fails')
    mapping.write_text('old-binary\t-\n')
    result = subprocess.run(args, capture_output=True, text=True)
    assert result.returncode == 0 and 'EXTERNAL-NOT-DEBIAN' in result.stdout, result
    print('GREEN: an explicitly external archive key has no invented Debian source')
