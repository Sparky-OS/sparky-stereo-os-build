#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Install audited receipts only for the exact stripped binaries tested."""
import hashlib
import json
from pathlib import Path
import sys
from catalogue import eligible

manifest=Path(sys.argv[1])
catalogue=Path(sys.argv[2])
library=Path(sys.argv[3])
entries=json.loads(catalogue.read_text())
proofs=json.loads(manifest.read_text())
assert len(proofs)==130 and len({item['id'] for item in proofs})==130
inventory={item['id']:item for item in json.loads((Path(__file__).parent/'audit/inventory-6.09.json').read_text()) if item['kind']=='hack'}
assert {item['id'] for item in proofs}==set(inventory)
layer_hash=hashlib.sha256(library.read_bytes()).hexdigest()
for item in proofs:
    assert item['command'][0]=='/usr/libexec/xscreensaver/'+item['id']
    assert item['proof']['passed'] is True and item['proof']['placement']=='screen-level'
    assert item['library_sha256']==layer_hash,(item['id'],'untested layer binary')
    assert hashlib.sha256(Path(item['command'][0]).read_bytes()).hexdigest()==item['executable_sha256'],(item['id'],'untested saver binary')
    assert item['qualification']['group'] in ('layer','owning-fix','flat')
    assert item['verification']['stock_2d_exact'] is True
    assert item['verification']['settings_unchanged'] is True
    assert item['verification']['kwin_composition'] is True
    assert item['verification']['camera_or_flat'] is True
    assert eligible(dict(item,library=str(library))),(item['id'],'ineligible camera proof')
    settings=Path('/usr/share/xscreensaver/config')/(item['id']+'.xml')
    assert hashlib.sha256(settings.read_bytes()).hexdigest()==item['verification']['settings_sha256']==inventory[item['id']]['settings_sha256']
    item['library']='/usr/lib/gl-stereo/libgl-stereo.so'
    item['environment']['LD_PRELOAD']=item['library']
entries=[item for item in entries if item['id'] in ('rocks','starfield')]
assert {item['id'] for item in entries}=={'rocks','starfield'}
for item in entries:
    item['qualification']=dict(state='qualified',group='owning-fix' if item['id']=='rocks' else 'layer')
entries+=proofs
catalogue.write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n')
print('PASS: 132 receipts bind the tested stripped binaries and complete saver proofs')
