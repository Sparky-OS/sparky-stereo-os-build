#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check caption sampling, including transparent-corner contamination."""
import json,subprocess,sys
from pathlib import Path
import numpy as np
from PIL import Image
out=Path(sys.argv[1]);out.mkdir(exist_ok=False)
base=np.zeros((1080,3840,3),dtype=np.uint8)
random=np.random.default_rng(73)
mask=random.integers(0,2,(15,100),dtype=np.uint8).astype(bool)
base[835:850,500:600][mask]=255
base[835:850,2422:2522][mask]=255
for name,expected in [('baseline',0),('rounded-corner-background',0),('changed-text-pixel',1)]:
 folder=out/name;folder.mkdir();pixels=base.copy()
 if name=='rounded-corner-background':pixels[926,3645]=245
 if name=='changed-text-pixel':
  dy,dx=np.argwhere(mask)[0];pixels[835+dy,2422+dx]=0
 for case in ('desktop','video'):
  Image.fromarray(pixels).save(folder/(case+'.pns'),format='PNG')
  (folder/('windows-'+case+'.json')).write_text(json.dumps({'windows':[{'cls':'kaption','hidden':False,'fg':[154,648,1228,96],'layer':9}]}))
 analyzer=Path(__file__).with_name('analyze-eyes.py')
 if not analyzer.exists():analyzer=Path(__file__).parent/'installed/analyze-eyes.py'
 subprocess.run([sys.executable,'-B',str(analyzer),str(folder),'1.25'],check=True,capture_output=True)
 values=json.loads((folder/'eye-measurements.json').read_text())
 assert all(v['left_minus_right_px']==-2 and v['glyph_xor_pixels']==expected for v in values),values
 print(name,'expected glyph XOR',expected,'found',[v['glyph_xor_pixels'] for v in values])
