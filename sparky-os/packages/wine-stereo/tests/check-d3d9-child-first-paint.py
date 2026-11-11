#!/usr/bin/env python3
"""Check the first WM_PAINT after show/reparent before another Present can run.

Input: the isolated capture directory with result.json, PNGs, client.stdout,
atoms.json and raw XRecord requests decoded as wire.jsonl.
"""
import json,re,sys
from pathlib import Path
from PIL import Image
import numpy as np

root=Path(sys.argv[1]);r=json.load(open(root/'result.json'));assert r['returncode']==0
assert [p['phase'] for p in r['phases']]==list(range(6))
log=(root/'client.stdout').read_text()
counts=[tuple(map(int,m)) for m in re.findall(r'phase=(\d+).*presents=(\d+) paints=(\d+)',log)]
assert [p[1] for p in counts]==[12,12,13,14,14,14]
assert counts[2][2]==counts[1][2]+1
atoms=json.load(open(root/'atoms.json'));wire=[json.loads(l) for l in (root/'wire.jsonl').read_text().splitlines()]
content=[t for t in wire if t['opcode']==18 and t.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT']]
assert len(content)==1 and content[0]['value']==[3]
child=content[0]['window'];rows=[]
for p in r['phases']:
 stage=p['phase'];visible=stage in (0,2,3);views=2 if visible else 1
 image=np.asarray(Image.open(root/f'phase{stage}-screen.png').convert('RGB'))
 assert image.shape==(600,800*views,3)
 title='D3D9 Owner '+('B' if stage>=3 else 'A')
 owner=next(w for w in p['all_windows'] if w['title']==title)
 native=next((w for w in p['all_windows'] if w['id']==child),None)
 row={'phase':stage,'raw_wrong':None,'capture_wrong':0,'capture_pixels':0}
 if stage<4:
  assert native and native['parent']==owner['id'] and native['mapped']==visible
  assert owner['properties']['_KDE_NET_WM_STEREO_CONTENT_CHILDREN']==[child]
 if stage==4:assert native and not native['mapped']
 if stage==5:assert native is None
 if visible:
  n=next(w for w in p['windows'] if w.get('id')==child and w.get('named_pixmap'))
  raw=np.asarray(Image.open(root/f'phase{stage}-pixmap{n["named_pixmap"]["id"]}.png').convert('RGB'))
  y,x=np.indices((200,320));expected=np.stack((x%160,199-y,(x//160)*128|stage),axis=2)
  row['raw_wrong']=int(np.any(raw!=expected,axis=2).sum())
 for name in ('D3D9 Owner A','D3D9 Owner B'):
  o=next(w for w in p['all_windows'] if w['title']==name);assert not o['declaration']
  if name!=title or stage>=4:assert not o['properties'].get('_KDE_NET_WM_STEREO_CONTENT_CHILDREN')
  for eye in range(views):
   expected=np.zeros((240,320,3),dtype=np.uint8)
   if name==title:
    if visible:
     y,x=np.indices((200,320));expected[:200]=np.stack((x//2,199-y,np.full_like(x,eye*128|stage)),axis=2)
    expected[40:88,80:144]=106
   actual=image[o['y']:o['y']+240,o['x']+eye*800:o['x']+eye*800+320]
   row['capture_wrong']+=int(np.any(actual!=expected,axis=2).sum());row['capture_pixels']+=76800
 # A timestamp is recorded after capture while the application still waits.
 previous=r['phases'][stage-1]['capture_monotonic'] if stage else 0
 row['present_requests']=sum(t.get('extension')=='Present' and t.get('minor') in (1,5) and t.get('window')==child and previous<t['monotonic']<=p['capture_monotonic'] for t in wire)
 assert row['present_requests']==([12,0,1,1,0,0][stage]),row
 rows.append(row)
out={'pass':not any(p['raw_wrong'] not in (None,0) or p['capture_wrong'] for p in rows),'counts':counts,'content_writes':1,'content_deletes':sum(t['opcode']==19 and t.get('atom')==atoms['_KDE_NET_WM_STEREO_CONTENT'] for t in wire),'actual_destroy_requests':sum(t['opcode']==4 and t.get('window')==child for t in wire),'rows':rows}
print(json.dumps(out,indent=2));raise SystemExit(0 if out['pass'] else 1)
