#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Diagnostic sweep only: successful depth probes are not qualification receipts."""
import json
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from controller import read_display

inventory=Path(sys.argv[1])
root=Path(sys.argv[2]); root.mkdir(parents=True,exist_ok=False)
checker=Path(sys.argv[3])
entries=json.loads(inventory.read_text())
if len(sys.argv)>4: entries=[entry for entry in entries if entry['id'] in sys.argv[4:]]
results=[]
for entry in entries:
    if entry['kind'] != 'hack': continue
    name=entry['id']; directory=root/name; directory.mkdir(exist_ok=True)
    result=dict(id=name, qualification='pending', compositor='Xvfb diagnostic, not Stereo KWin')
    server=process=None
    server_log=(directory/'xserver.log').open('w')
    try:
        assert hashlib.sha256(Path(entry['command'][0]).read_bytes()).hexdigest() == entry['executable_sha256'], 'installed executable changed since inventory'
        read,write=os.pipe()
        server=subprocess.Popen(['Xvfb','-displayfd',str(write),'-screen','0','2560x1440x24','-ac','-noreset','-nolisten','tcp'],pass_fds=(write,),stdout=server_log,stderr=server_log)
        os.close(write)
        try:
            display=read_display(read)
        finally: os.close(read)
        env={k:v for k,v in os.environ.items() if not k.startswith('GL_STEREO') and k not in ('DISPLAY','WAYLAND_DISPLAY','LD_PRELOAD','XAUTHORITY')}
        env.update(DISPLAY=display,LIBGL_ALWAYS_SOFTWARE='1',GALLIUM_DRIVER='llvmpipe',LP_NUM_THREADS='4',
                   PATH='/usr/libexec/xscreensaver:'+os.environ.get('PATH',os.defpath),
                   LD_PRELOAD='/usr/lib/gl-stereo/libgl-stereo.so',GL_STEREO='1',GL_STEREO_LOG='1',
                   GL_STEREO_DUMP='30',GL_STEREO_DUMP_DIR=str(directory.resolve()))
        with (directory/'producer.log').open('w') as log:
            process=subprocess.Popen(entry['command'],env=env,stdout=log,stderr=log,start_new_session=True)
            deadline=time.monotonic()+8
            while time.monotonic()<deadline and process.poll() is None:
                if list(directory.glob('frame-*.txt')): break
                time.sleep(.05)
            result['producer_exit']=process.poll()
            result['captured']=bool(list(directory.glob('frame-*.txt')))
        if result['captured']:
            frame=sorted(directory.glob('frame-*.ppm'))[-1]
            image=np.array(Image.open(frame).convert('RGB'))
            h,w,_=image.shape
            result['size']=[w,h]
            assert w%2==0
            left,right=image[:,:w//2],image[:,w//2:]
            result['nonempty']=[float((eye.max(axis=2)>32).mean()) for eye in (left,right)]
            result['stddev']=[float(eye.std()) for eye in (left,right)]
            result['different_pixels']=float(np.any(left!=right,axis=2).mean())
            Image.fromarray(left).save(directory/'LEFT.png')
            Image.fromarray(right).save(directory/'RIGHT.png')
            with (directory/'depth-oracle.log').open('w') as log:
                check=subprocess.run([sys.executable,str(checker),str(directory)],stdout=log,stderr=log)
            result['depth_oracle']=check.returncode==0
            if check.returncode==0: result['depth']=json.loads((directory/'result.json').read_text())
        else: result['depth_oracle']=False
        result['layer_warnings']=[line for line in (directory/'producer.log').read_text(errors='replace').splitlines() if line.startswith('gl-stereo:')]
    except Exception as error:
        result['error']=str(error)
    finally:
        if process:
            try: os.killpg(process.pid,signal.SIGTERM)
            except ProcessLookupError: pass
            try: process.wait(timeout=2)
            except subprocess.TimeoutExpired: os.killpg(process.pid,signal.SIGKILL); process.wait()
        if server:
            server.terminate()
            try: server.wait(timeout=3)
            except subprocess.TimeoutExpired: server.kill(); server.wait()
        server_log.close()
        for path in directory.glob('frame-*'): path.unlink()
    results.append(result)
    (root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(len(results),name,'capture',result.get('captured'),'depth',result.get('depth_oracle'),flush=True)
assert len(results)==sum(entry['kind']=='hack' for entry in entries)
print(f'COMPLETE: {len(results)} diagnostic probes; none promoted to qualified by this sweep',flush=True)
