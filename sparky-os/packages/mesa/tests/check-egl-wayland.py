#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check raw pixels, compositor captures and actual driver protocol requests."""
import argparse,json,re
from pathlib import Path
import numpy as np
from PIL import Image

STAGES={'first':(96,64),'resize':(80,48),'repeat':(80,48),'recreated':(96,64)}
def expected(width,height,eye):
 y,x=np.indices((height,width));return np.stack((x+17,height-1-y+31,np.full_like(x,201 if eye else 73)),axis=2).astype(np.uint8)
def captured(image,width,height,eye):
 mask=(image[:,:,2]==(201 if eye else 73))&(image[:,:,0]>=17)&(image[:,:,0]<17+width)&(image[:,:,1]>=31)&(image[:,:,1]<31+height)
 y,x=np.where(mask);assert len(x)==width*height,('pixel support',eye,len(x),width*height)
 box=(int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1));l,t,r,b=box
 assert (r-l,b-t)==(width,height),('geometry',box)
 assert np.array_equal(image[t:b,l:r],expected(width,height,eye)),('captured eye differs',eye)
 return box

def protocol(log,mode,surfaces):
 lines=log.splitlines();creates=[];sets=[];destroys=[];sizes=[];buffers={}
 active={};created_surfaces=[];declarations={}
 for index,line in enumerate(lines):
  if ' -> ' not in line:continue
  m=re.search(r'wl_compositor#\d+\.create_surface\(new id wl_surface#(\d+)\)',line)
  if m:created_surfaces.append(int(m[1]))
  m=re.search(r'wl_surface#(\d+)\.destroy\(\)',line)
  if m:
   surface=int(m[1]);assert surface not in active.values();declarations.pop(surface,None)
  m=re.search(r'kde_stereo_content_manager_v1#\d+\.create\(new id kde_stereo_content_v1#(\d+), wl_surface#(\d+)\)',line)
  if m:
   content,surface=map(int,m.groups());assert content not in active and surface not in declarations
   active[content]=surface;declarations[surface]={'create':index};creates.append({'content_id':content,'surface_id':surface,'line':index})
  m=re.search(r'kde_stereo_content_v1#(\d+)\.set_content\((\d+)\)',line)
  if m:
   content,value=map(int,m.groups());assert value==3 and content in active
   surface=active[content];assert 'set' not in declarations[surface];declarations[surface]['set']=index;sets.append(index)
  m=re.search(r'kde_stereo_content_v1#(\d+)\.destroy\(\)',line)
  if m:
   content=int(m[1]);assert content in active;active.pop(content);destroys.append(index)
  m=re.search(r'create_immed\(new id wl_buffer#(\d+), (\d+), (\d+),',line)
  if m:buf,w,h=map(int,m.groups());buffers[buf]=(w,h)
  m=re.search(r'wl_surface#(\d+)\.attach\(wl_buffer#(\d+),',line)
  if m:
   surface,buf=map(int,m.groups());assert surface in surfaces and buf in buffers
   sizes.append({'surface':surface,'buffer':buf,'size':list(buffers[buf]),'attach_line':index})
  m=re.search(r'wl_surface#(\d+)\.commit\(\)',line)
  if m and sizes and sizes[-1]['surface']==int(m[1]) and 'commit_line' not in sizes[-1]:
   surface=int(m[1]);sizes[-1]['commit_line']=index
   if mode=='stereo':assert declarations.get(surface,{}).get('set',index+1)<index,'first buffer committed before declaration'
 assert created_surfaces==surfaces and len(surfaces)==2 and not active and not declarations
 want=2 if mode=='stereo' else 0
 assert len(creates)==len(sets)==len(destroys)==want,(mode,creates,sets,destroys)
 assert len(sizes)==4
 assert [r['size'] for r in sizes]==[[w*(2 if mode=='stereo' else 1),h] for w,h in STAGES.values()]
 assert all('commit_line' in r for r in sizes)
 assert not re.search(r' -> wp_viewport#\d+\.set_(?:source|destination)',log),'v2 must leave viewport ownership to client'
 assert re.search(r'bind\(\d+, "kde_stereo_content_manager_v1", 2,',log)
 return {'created_surfaces':surfaces,'content_creates':creates,'set_content_count':len(sets),'content_destroy_count':len(destroys),'attached_buffers':sizes,'viewport_writes':0}

def rejects(fn):
 try:fn()
 except AssertionError:return True
 raise AssertionError('negative control was accepted')

def main():
 p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('--output',type=Path,required=True);args=p.parse_args();rows=[];images={};negatives=[]
 for mode in ('mono','left-only','stereo'):
  root=args.root/mode;result=json.loads((root/'result.json').read_text());assert result['returncode']==0 and result['failure'] is None
  assert not result['environment'].get('DISPLAY') and not result['environment'].get('LD_LIBRARY_PATH')
  assert all(v['elf_class']!=1 for v in result['mapped'].values())
  stdout=(root/'client.stdout').read_text();assert stdout.rstrip().endswith('PASS')
  surfaces=[int(x) for x in re.findall(r'^SURFACE id=(\d+)',stdout,re.M)]
  log=(root/'protocol.log').read_text();wire=protocol(log,mode,surfaces)
  pixels=[];images[mode]={}
  for stage,(w,h) in STAGES.items():
   image=np.array(Image.open(root/(stage+'.png')).convert('RGB'));assert image.shape==(600,1600 if mode=='stereo' else 800,3)
   boxes=[]
   for eye in range(2 if mode=='stereo' else 1):
    raw=np.frombuffer((root/f'{stage}-eye{eye}.rgb').read_bytes(),np.uint8).reshape(h,w,3)[::-1]
    assert np.array_equal(raw,expected(w,h,eye)),(mode,stage,eye,'raw pixels')
    boxes.append(captured(image,w,h,eye));pixels.append({'stage':stage,'eye':eye,'checked_pixels':w*h,'raw_errors':0,'captured_errors':0,'box':boxes[-1]})
   if mode=='stereo':assert boxes[1]==(boxes[0][0]+800,boxes[0][1],boxes[0][2]+800,boxes[0][3])
   images[mode][stage]=(image,boxes)
  assert not np.any(np.array(Image.open(root/'exit.png').convert('RGB'))),'exit did not restore black screen'
  rows.append({'mode':mode,'protocol':wire,'pixels':pixels})
  if mode=='stereo':
   negatives.append({'changed_declaration_rejected':rejects(lambda:protocol(log.replace('.set_content(3)','.set_content(1)',1),mode,surfaces))})
   line=next(s for s in log.splitlines() if '.set_content(3)' in s)
   negatives.append({'missing_declaration_rejected':rejects(lambda:protocol(log.replace(line,'',1),mode,surfaces))})
   negatives.append({'duplicate_declaration_rejected':rejects(lambda:protocol(log.replace(line,line+'\n'+line,1),mode,surfaces))})
   negatives.append({'wrong_buffer_width_rejected':rejects(lambda:protocol(log.replace(', 192, 64,',', 191, 64,',1),mode,surfaces))})
 for stage,(w,h) in STAGES.items():
  mono,mb=images['mono'][stage];left,lb=images['left-only'][stage];stereo,sb=images['stereo'][stage]
  assert np.array_equal(mono,left),'left-only changed ordinary presentation'
  assert mb[0]==lb[0]==sb[0],'one-view geometry differs'
  assert np.array_equal(stereo[:,:800],mono),'stereo left view differs from ordinary window'
  l,t,r,b=sb[0];changed=stereo.copy();changed[t,l,0]^=1
  negatives.append({'stage':stage,'one_pixel_change_rejected':rejects(lambda:captured(changed,w,h,0))})
  swapped=stereo.copy();swapped[:,:800],swapped[:,800:]=stereo[:,800:].copy(),stereo[:,:800].copy()
  negatives.append({'stage':stage,'swapped_eyes_rejected':rejects(lambda:np.testing.assert_array_equal(swapped[t:b,l:r],expected(w,h,0)))})
  frozen=stereo.copy();frozen[:,800:]=stereo[:,:800]
  negatives.append({'stage':stage,'frozen_eye_rejected':rejects(lambda:captured(frozen,w,h,1))})
 output={'status':'PASS','scope':'Native Wayland EGL, AMD render node, installed modules; no Wine/NVIDIA/DXVK claim','cases':rows,'negative_controls':negatives,'raw_pixels_checked':sum(r['checked_pixels'] for row in rows for r in row['pixels']),'captured_pixels_checked':sum(r['checked_pixels'] for row in rows for r in row['pixels'])}
 args.output.write_text(json.dumps(output,indent=2)+'\n');print('PASS',output['raw_pixels_checked'],'raw and captured pixels;',len(negatives),'negative controls')
if __name__=='__main__':main()
