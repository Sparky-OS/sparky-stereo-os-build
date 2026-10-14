# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from catalogue import load
base=Path(__file__).resolve().parent
inventory=json.loads((base/'inventory-6.09.json').read_text())
results=json.loads((base/'diagnostic-6.09.json').read_text())
assert len(inventory)==131 and len(results)==130
assert {e['id'] for e in inventory if e['kind']=='hack'} == {e['id'] for e in results}
assert all(e['qualification']['state']=='pending' for e in inventory)
assert all(e['qualification']=='pending' for e in results)
assert not load(base/'inventory-6.09.json')
assert not load(base/'diagnostic-6.09.json')
assert sum(bool(e.get('captured')) for e in results)==127
assert sum(bool(e.get('depth_oracle')) for e in results)==68
assert sum(e.get('different_pixels')==0 for e in results)==19
assert '@' not in (base/'inventory-6.09.json').read_text()
print('PASS: exact 130-saver coverage, helper retained, counts consistent, both audit files excluded from trusted rotation')
