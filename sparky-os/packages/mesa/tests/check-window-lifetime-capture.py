#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
from pathlib import Path
import json,sys,re,struct
from PIL import Image
p=Path(sys.argv[1]);rows=[];ui=[]
captures=json.loads((p/'captures.json').read_text())
expected_stages=['two-children','drawable-destroyed-window-alive','drawable-recreated','reparent-before-next-swap','reparent-after-swap','reparent-drawable-recreated','window-destroy-before-next-swap','other-child-next-swap','both-windows-destroyed']
assert [c['stage'] for c in captures]==expected_stages
for stage_index,c in enumerate(captures):
 expected_indices=[0,1,2,3] if stage_index<6 else [0,1,3] if stage_index<8 else [0,1]
 assert sorted(g['index'] for g in c['geometry'])==expected_indices
 assert c['capture']['stereo']==(stage_index<8)
 for g in c['geometry']:
  expected=[(20,20,320,260),(370,20,320,260),(380 if stage_index>=3 else 30,70,120,100),(170,70,120,100)][g['index']]
  assert tuple(g[k] for k in ['x','y','width','height'])==expected and g['mapped']
 im=Image.open(p/(c['stage']+'.png')).convert('RGB');assert im.size==(c['capture']['width'],600)
 for g in c['geometry']:
  if g['index']<2:continue
  index=g['index']-2
  for eye in [0,1]:
   pixels=im.crop((g['x']+800*eye,g['y'],g['x']+g['width']+800*eye,g['y']+g['height'])).tobytes();expected=bytes((0,64*index,255) if eye else (255,64*index,0))
   rows.append({'stage':c['stage'],'child':index,'eye':eye,'pixels':len(pixels)//3,'mismatches':sum(pixels[i:i+3]!=expected for i in range(0,len(pixels),3))})
 bad=count=0
 for g in c['geometry']:
  if g['index']>=2:continue
  for eye in range(2 if c['capture']['stereo'] else 1):
   for y in range(g['y'],g['y']+g['height']):
    for x in range(g['x'],g['x']+g['width']):
     if any(h['index']>=2 and h['x']<=x<h['x']+h['width'] and h['y']<=y<h['y']+h['height'] for h in c['geometry']):continue
     count+=1;bad+=im.getpixel((x+eye*800,y))!=(32,64,96)
 ui.append({'stage':c['stage'],'pixels':count,'mismatches':bad})
raw=[]
for frame,index in enumerate([0,1,0,0,0,1]):
 for eye in [0,1]:
  expected=bytes((0,index*64,255) if eye else (255,index*64,0));b=(p/f'frame{frame}-eye{eye}.rgb').read_bytes();assert len(b)==36000
  raw.append({'frame':frame,'eye':eye,'pixels':12000,'mismatches':sum(b[i:i+3]!=expected for i in range(0,len(b),3))})
text=(p/'client.stdout').read_text();content_atom,children_atom=map(int,re.search(r'ATOMS content=(\d+) children=(\d+)',text).groups());ids=list(map(int,re.search(r'IDS ownerA=(\d+) ownerB=(\d+) childA=(\d+) childB=(\d+)',text).groups()))
writes={'content':[],'owner_list':[]};presents=[]
for line in (p/'wire.jsonl').read_text().splitlines():
 r=json.loads(line)
 if 'extensions' in r:present_opcode=r['extensions']['Present'];continue
 if 'hex' not in r:continue
 b=bytes.fromhex(r['hex'])
 if b[0]==18:
  w,a,t=struct.unpack_from('<III',b,4)
  if a in [content_atom,children_atom]:writes['content' if a==content_atom else 'owner_list'].append({'window':w,'time':r['monotonic'],'payload':b[24:].hex()})
 if b[0]==present_opcode and b[1]==1:presents.append({'window':struct.unpack_from('<I',b,4)[0],'time':r['monotonic']})
settled=re.findall(r'SETTLED stage=(\S+) polls=(\d+) matched=(\d+)',text)
result={'case':str(p),'raw':raw,'captures':rows,'ordinary_ui':ui,'writes':writes,'presents':presents,'settled':settled}
result['pass']=all(r['mismatches']==0 for r in rows+raw+ui) and len(settled)==9 and all(x[2]=='1' for x in settled) and len(writes['content'])==2 and len(writes['owner_list'])==6
result['declared_before_first_present']=all(next(w['time'] for w in writes['content'] if w['window']==child)<next(w['time'] for w in presents if w['window']==child) for child in ids[2:])
Path(sys.argv[2]).write_text(json.dumps(result,indent=2)+'\n');print({'pass':result['pass'],'declaration_order':result['declared_before_first_present'],'raw_bad':sum(r['mismatches'] for r in raw),'captured_bad':sum(r['mismatches'] for r in rows),'ui_bad':sum(r['mismatches'] for r in ui),'captured_pixels':sum(r['pixels'] for r in rows),'ui_pixels':sum(r['pixels'] for r in ui)})
if '--require-pass' in sys.argv:assert result['pass'] and result['declared_before_first_present']
