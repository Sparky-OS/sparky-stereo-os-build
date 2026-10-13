# SPDX-License-Identifier: GPL-2.0-or-later
"""Relocate validated build receipts without changing their binary hashes."""
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'savers'))
from catalogue import load

source, output, prefix = sys.argv[1:]
entries = load(source)
assert entries, 'no validated savers to package'
for entry in entries:
    if entry['id'] in ('starfield', 'rocks'):
        entry['command'][0] = prefix + '/lib/gl-stereo/savers/' + entry['id']
    entry['library'] = prefix + '/lib/gl-stereo/libgl-stereo.so'
    if 'LD_PRELOAD' in entry['environment']:
        entry['environment']['LD_PRELOAD'] = entry['library']
Path(output).parent.mkdir(parents=True, exist_ok=True)
Path(output).write_text(json.dumps(entries, indent=2) + '\n')
