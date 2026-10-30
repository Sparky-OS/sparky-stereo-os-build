#!/usr/bin/env python3
"""Check paused-move raw pixmaps, delivered eyes, clip and final ordinary UI.

Pass the isolated rig directory containing result.json, atoms.json, wire.jsonl
and its lossless phase PNGs. An incorrect retained image exits nonzero.
"""
import json,sys
from pathlib import Path
from PIL import Image
import numpy as np
root=Path(sys.argv[1]);result=json.load(open(root/'result.json'));assert result['returncode']==0
assert [p['phase'] for p in result['phases']]==[0,1,2,3]
rows=[]
for p in result['phases']:
 stage=p['phase'];image=np.asarray(Image.open(root/f'phase{stage}-screen.png').convert('RGB'))
 assert image.shape==(600,1600 if stage<2 else 800,3)
 row={'phase':stage,'raw_wrong':None,'capture_wrong':0,'capture_pixels':0}
 if stage<2:
  native=next(w for w in p['windows'] if w.get('declaration'))
  pixmap=native['named_pixmap'];raw=np.asarray(Image.open(root/f'phase{stage}-pixmap{pixmap["id"]}.png').convert('RGB'))
  y,x=np.indices((200,320));expected=np.stack((x%160,199-y,(x//160)*128),axis=2)
  row['raw_wrong']=int(np.any(raw!=expected,axis=2).sum())
  assert native['properties']['_KDE_NET_WM_STEREO_CONTENT_CHILD_PLACE']==([16,16,320,200,0] if stage else [0,0,320,200,0])
  mask=np.zeros((200,320),dtype=bool)
  for rect in native['bounding_shape']:mask[rect['y']:rect['y']+rect['height'],rect['x']:rect['x']+rect['width']]=True
  wanted=np.zeros_like(mask);off=16 if stage else 0
  for eye in range(2):
   wanted[:,eye*160:eye*160+160-off//2]=True
   wanted[40-off:88-off,eye*160+(80-off)//2:eye*160+(144-off)//2]=False
  assert np.array_equal(mask,wanted)
 for title in ('D3D9 Owner A','D3D9 Owner B'):
  owner=next(w for w in p['all_windows'] if w['title']==title)
  assert not owner['declaration']
  for eye in range(image.shape[1]//800):
   expected=np.zeros((240,320,3),dtype=np.uint8)
   if title=='D3D9 Owner A':
    if stage<2:
     off=16 if stage else 0;y,x=np.indices((200,320-off))
     expected[off:off+200,off:]=np.stack((x//2,199-y,np.full_like(x,eye*128)),axis=2)
    expected[40:88,80:144]=106
   actual=image[owner['y']:owner['y']+240,owner['x']+eye*800:owner['x']+eye*800+320]
   row['capture_wrong']+=int(np.any(actual!=expected,axis=2).sum());row['capture_pixels']+=76800
 rows.append(row)
atoms=json.load(open(root/'atoms.json'));wire=[json.loads(l) for l in (root/'wire.jsonl').read_text().splitlines()]
content=[r for r in wire if r['opcode']==18 and r.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT']]
assert len(content)==1 and content[0]['value']==[3];child=content[0]['window']
out={'pass':not any(r['raw_wrong'] not in (None,0) or r['capture_wrong'] for r in rows),'rows':rows,'child':child,'content_writes':1,'native_reparents':sum(r['opcode']==7 and r.get('window')==child for r in wire),'native_configures':sum(r['opcode']==12 and r.get('window')==child for r in wire),'native_destroy_requests':sum(r['opcode']==4 and r.get('window')==child for r in wire)}
print(json.dumps(out,indent=2));raise SystemExit(0 if out['pass'] else 1)
