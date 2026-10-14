#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Retain the entire installed saver inventory, independently of eligibility."""
import json
from pathlib import Path
import sys
entries=json.loads((Path(__file__).parent/'audit/inventory-6.09.json').read_text())
entries += [dict(id='starfield',kind='hack',title='Starfield',authors=['Sparky Stereo OS'],qualification=dict(state='pending',group=None)),
            dict(id='rocks',kind='hack',title='Rocks',authors=['Jamie Zawinski','Johannes Keukelaar','John Nguyen'],qualification=dict(state='pending',group=None))]
if len(sys.argv)>2:
    catalogue={entry['id']:entry for entry in json.loads(Path(sys.argv[2]).read_text())}
    for entry in entries:
        if entry['id'] in catalogue:
            entry['qualification']=catalogue[entry['id']].get('qualification',dict(state='qualified',group='layer'))
output=Path(sys.argv[1]); output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n')
