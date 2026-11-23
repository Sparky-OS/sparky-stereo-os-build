# SPDX-License-Identifier: GPL-2.0-or-later
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
from pathlib import Path
import sys,json,re,subprocess,hashlib
import numpy as np
from PIL import Image
out=Path(sys.argv[1]);inputs=Path(sys.argv[2]);spec=json.loads((out/'spec.json').read_text());state=json.loads((out/'frame.json').read_text());rows=[]
def row(name,expected,found):rows.append(dict(row=name,expected=expected,found=found,passed=expected==found))
expected=np.frombuffer((inputs/'expected.raw').read_bytes(),np.uint8).reshape(spec['eyeHeight'] if spec['stereo'] else spec['height'],spec['eyeWidth']*2 if spec['stereo'] else spec['width'],4)
delivered=np.frombuffer((out/'delivered.raw').read_bytes(),np.uint8).reshape(state['height'],state['width'],4)
row('delivered dimensions',list(expected.shape),list(delivered.shape))
row('delivered differing samples',0,int(np.count_nonzero(expected!=delivered)) if expected.shape==delivered.shape else -1)
log=(out/'kamoso.log').read_text(errors='replace');declarations=log.count('.set_content(3)')
row('one child declaration' if spec['stereo'] else 'mono not declared',int(spec['stereo']),declarations)
binds=[l for l in log.splitlines() if re.search(r'wl_registry#\d+\.bind\(.*"wl_output"',l)]
row('only Qt owns wl_output binding',True,len(binds)==1 and 'Default Queue' in binds[0]);(out/'output-bindings.json').write_text(json.dumps(binds,indent=2))
records=[];differences=0
if (out/'buffer-audit.json').exists():
 records=json.loads((out/'buffer-audit.json').read_text());differences=sum(abs(r['differingSamples']) for r in records)
if (out/'log.jsonl').exists():
 for line in (out/'log.jsonl').read_text().splitlines():
  r=json.loads(line);p=out/r['file']
  if not p.exists():continue
  raw=p.read_bytes();a=np.frombuffer(raw,np.uint8).reshape(r['height'],r['stride'])[:,:r['width']*4].reshape(r['height'],r['width'],4)[:,:,[2,1,0,3]]
  difference=int(np.count_nonzero(a!=expected)) if a.shape==expected.shape else -1
  r.update(sha256=hashlib.sha256(raw).hexdigest(),differingSamples=difference)
  differences+=abs(difference);records.append(r);p.unlink()
if spec['stereo']:
 row('submitted buffers exist',True,bool(records));row('submitted differing samples',0,differences)
 row('recorder limit not reached',True,len(records)<4096)
(out/'buffer-audit.json').write_text(json.dumps(records,indent=2))
info=json.loads((out/'capture.json').read_text());stereoOutput=info['stereoOutput'];cap=np.asarray(Image.open(out/('capture.pns' if stereoOutput else 'capture.png')).convert('RGB'))
win=next(w for w in json.loads((out/'windows.json').read_text())['windows'] if w['cls']=='org.kde.kamoso')
if records:
 r=records[-1];x,y=r['position'];w,h=r['destination']
else:x,y,w,h=map(round,state['view'])
x+=win['cg'][0];y+=win['cg'][1]
row('view inside output',True,0<=x and 0<=y and x+w<=1920 and y+h<=1080)
comparisons=[]
for eye in range(2 if stereoOutput else 1):
 ref=expected[:,:spec['eyeWidth'],:3] if eye==0 or not spec['stereo'] else expected[:,spec['eyeWidth']:,:3]
 # Raw RGB pipes avoid leaving an unmarked half-pair image in the evidence.
 process=subprocess.run(['ffmpeg','-v','error','-threads','1','-f','rawvideo','-pix_fmt','rgb24','-s',f'{ref.shape[1]}x{ref.shape[0]}','-i','pipe:0','-vf',f'scale={w}:{h}:flags=bilinear','-frames:v','1','-threads','1','-f','rawvideo','-pix_fmt','rgb24','pipe:1'],input=ref.tobytes(),stdout=subprocess.PIPE,check=True)
 scaled=np.frombuffer(process.stdout,np.uint8).reshape(h,w,3)
 actual=cap[y:y+h,x+eye*1920:x+eye*1920+w]
 mask=np.ones((h,w),bool)
 if not stereoOutput:
  nx,ny,nw,nh=state['noticeRect'];nx+=win['cg'][0];ny+=win['cg'][1]
  xa=max(0,int(np.floor(nx-x)));xb=min(w,int(np.ceil(nx+nw-x)))
  ya=max(0,int(np.floor(ny-y)));yb=min(h,int(np.ceil(ny+nh-y)))
  mask[ya:yb,xa:xb]=False
  row('named left-eye notice has drawn pixels',True,bool(np.any(actual[ya:yb,xa:xb]!=scaled[ya:yb,xa:xb])))
  (out/'named-overlay.json').write_text(json.dumps(dict(element='This display is in 2D. Showing the left eye.',sceneRect=[nx,ny,nw,nh],excludedSamples=int(np.count_nonzero(~mask)*3),check='visible text property and drawn pixels'),indent=2))
 mse=np.mean((actual.astype(float)-scaled)[mask]**2);psnr=100 if mse==0 else float(10*np.log10(255**2/mse))
 comparisons.append(dict(eye=eye,psnr=psnr,rect=[x,y,w,h],native=[ref.shape[1],ref.shape[0]]))
 row(f'eye {eye} matches one compositor resize at >=35 dB',True,psnr>=35)
if not stereoOutput:row('left-eye notice visible',True,state['leftEyeNoticeVisible'])
(out/'geometry.json').write_text(json.dumps(comparisons,indent=2));(out/'rows.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows));sys.exit(not all(r['passed'] for r in rows))
