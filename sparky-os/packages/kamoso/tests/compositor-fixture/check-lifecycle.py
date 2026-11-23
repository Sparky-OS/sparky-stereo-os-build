# SPDX-License-Identifier: GPL-2.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
from pathlib import Path
import json,sys
from PIL import Image
out=Path(sys.argv[1]);count=int(sys.argv[2])
lines=(out/'lifecycle.txt').read_text().splitlines()
assert lines==[f'cycle={n} hidden=true shown=true alive=true' for n in range(1,count+1)],lines
receipts=[json.loads(s) for s in (out/'action-receipts.jsonl').read_text().splitlines()]
assert len(receipts)==count*2 and all(r['triggered'] and r['invoked'] and r['checked']==r['desired'] for r in receipts)
image=Image.open(out/'after-fifty.pns').convert('RGB');source=Image.open(out/'source.pns').convert('RGB')
checks=[]
for eye in range(2):
 expected=source.getpixel((100+eye*640,100))
 for x in (750,1150):
  found=image.getpixel((x+eye*1920,550));checks.append(dict(eye=eye,x=x,expected=expected,found=found,passed=expected==found))
(out/'last-cycle-pixels.json').write_text(json.dumps(checks,indent=2));assert all(r['passed'] for r in checks),checks
print(f'{count} hide/show cycles acknowledged, alive after every show, last capture has both source eyes.')
