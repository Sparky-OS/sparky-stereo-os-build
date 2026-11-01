#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
import numpy as np
from PIL import Image
root=Path(sys.argv[1]);rows=[]
for mode in ('stereo',):
 log=(root/'client.stdout').read_text();captures=json.load(open(root/'captures.json'))
 assert 'NVIDIA GeForce RTX 3060' in log, 'wrong renderer'
 raw=[]
 for phase,kind,eye,w,h,bad,ge in re.findall(r'RAW phase=(\S+) buffer=(\S+) eye=(\d+) size=(\d+)x(\d+) errors=(\d+) gl_error=(\d+)',log):
  eye,w,h,bad,ge=map(int,(eye,w,h,bad,ge));stamp={'initial':1,'first-resize':2,'second-resize':3}[phase]
  yy,xx=np.indices((h,w));expected=np.stack((xx&255,yy&255,np.full((h,w),stamp|(eye<<7))),axis=2)
  actual=np.fromfile(root/f'{phase}-{kind}-{eye}.raw',dtype=np.uint8).reshape(h,w,3)
  measured=int(np.any(actual!=expected,axis=2).sum());assert measured==bad
  raw.append({'phase':phase,'buffer':kind,'eye':eye,'different_pixels':measured,'gl_error':ge})
 assert len(raw)==(12 if mode=='stereo' else 6)
 for cap in captures:
  phase=cap['phase'];stamp={'initial':1,'first-resize':2,'second-resize':3}[phase]
  child=next(x for x in cap['geometry'] if x['kind']=='child');owner=next(x for x in cap['geometry'] if x['kind']=='owner');w,h=child['width'],child['height'];x,y=child['x'],child['y']
  yy,xx=np.indices((h,w));expected=np.stack((xx&255,(h-1-yy)&255,np.full((h,w),stamp)),axis=2)
  im=np.asarray(Image.open(root/(phase+'.png'))).astype(int)
  assert im.shape==(600,1600 if mode=='stereo' else 800,3),('screen size',mode,phase,im.shape)
  pixel=[]
  for eye in range(2 if mode=='stereo' else 1):
   target=expected.copy();target[:,:,2]|=eye<<7
   actual=im[y:y+h,x+eye*800:x+eye*800+w]
   errors=int(np.any(actual!=target,axis=2).sum());pixel.append(errors)
  props=child['properties'];assert owner['properties']['_KDE_NET_WM_STEREO_CONTENT'] is None
  assert props['_KDE_NET_WM_STEREO_CONTENT']==([3] if mode=='stereo' else None)
  if mode=='stereo':
   assert props['_KDE_NET_WM_STEREO_CONTENT_VERSION']==[4]
   assert owner['properties']['_KDE_NET_WM_STEREO_CONTENT_CHILDREN']==[child['xid']]
  match=re.search(r'XIMAGE phase='+re.escape(phase)+r' size=(\d+)x(\d+) stride=(\d+) bpp=(\d+) order=(\d+) masks=(\w+),(\w+),(\w+)',log)
  assert match,'missing actual pixmap array'
  pw,ph,stride,bpp,order=map(int,match.groups()[:5]);assert (pw,ph)==(w*(2 if mode=='stereo' else 1),h),(phase,pw,ph,w,h)
  assert bpp==32 and order==0,(bpp,order)
  data=np.fromfile(root/f'{phase}-pixmap-0.raw',dtype=np.uint8).reshape(ph,stride)
  words=data[:,:pw*4].copy().view('<u4').reshape(ph,pw)
  actual=np.stack(((words>>16)&255,(words>>8)&255,words&255),axis=2)
  target=expected.copy()
  if mode=='stereo':
   right=expected.copy();right[:,:,2]|=128;target=np.concatenate((target,right),axis=1)
  pixmap_errors=int(np.any(actual!=target,axis=2).sum());assert pixmap_errors==0,(phase,'pixmap',pixmap_errors)
  row={'phase':phase,'mode':mode,'size':[w,h],'delivered_errors':pixel,'pixmap_errors':pixmap_errors,'raw':[r for r in raw if r['phase']==phase]};rows.append(row)
  assert all(e==0 for e in pixel),row
 assert all(r['different_pixels']==0 and r['gl_error']==0 for r in raw),raw
 assert len(re.findall(r'^COMPLETED .* pixmap=1 ',log,re.M))==3

(root/'strict-stereo.json').write_text(json.dumps({'status':'PASS','scope':'native stereo three held frames, all back/front pixels and delivered pixels','rows':rows},indent=2)+'\n')
print('PASS stereo',len(rows))
