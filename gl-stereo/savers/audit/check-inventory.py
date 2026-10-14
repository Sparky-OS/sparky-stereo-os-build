#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Preserve every installed saver, its settings and the original author records."""
import hashlib
import json
from pathlib import Path
import sys

original = {item['id']: item for item in json.loads(Path(sys.argv[1]).read_text())}
current = {item['id']: item for item in json.loads(Path(sys.argv[2]).read_text())}
assert original.keys() == current.keys() and len(current) == 131
changed = []
for name, item in current.items():
    for field in ('kind', 'owner', 'title', 'package', 'command', 'settings_sha256', 'authors', 'credit_records', 'source_files'):
        assert item[field] == original[name][field], (name, field)
    installed = Path('/usr/share/xscreensaver/config') / (item['owner'] + '.xml')
    assert hashlib.sha256(installed.read_bytes()).hexdigest() == item['settings_sha256'], name
    if item['executable_sha256'] != original[name]['executable_sha256']:
        changed.append(name)
print('PASS: all 131 payload entries, 130 unchanged settings files and source credits retained')
print('Executable differences from initial inventory:', ', '.join(changed) or 'none')
