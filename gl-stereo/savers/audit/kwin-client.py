# SPDX-License-Identifier: GPL-2.0-or-later
import json
import hashlib
import os
import re
from pathlib import Path
import signal
import subprocess
import sys
import time
from PIL import Image
import numpy as np
root=Path(sys.argv[1]); name=sys.argv[2]
target=os.environ.get('AUDIT_TARGET','120')
reference_eye=os.environ.get('AUDIT_REFERENCE_EYE')
library=os.environ.get('AUDIT_LIBRARY','/workspace/gl-stereo/libgl-stereo.so')
assert Path(library).is_file(), 'missing test library'
env=dict(os.environ,LD_PRELOAD=os.environ.get('AUDIT_FIXTURE','/build/fixture-egl.so')+':'+library,
         LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='4',GL_STEREO='1',GL_STEREO_DEBUG='1',GL_STEREO_DUMP=target,GL_STEREO_DUMP_DIR=str(root),
         PATH='/usr/libexec/xscreensaver:'+os.environ.get('PATH',os.defpath),
         AUDIT_FRAME=target,AUDIT_READY=str(root/'ready'))
if reference_eye:
    # Only the independent library is loaded. Keep Enable 3D set so owning
    # patches also expose their ordinary camera to this single-eye oracle.
    env.update(REFERENCE_EYE=reference_eye)
if os.environ.get('AUDIT_NO_FIXTURE'): env['LD_PRELOAD']='/workspace/gl-stereo/libgl-stereo.so'
with (root/'client.log').open('w') as log:
    # An open snapshot range keeps retrace from exiting at the selected call
    # before the parent can freeze its window for the KWin capture.
    command=['glretrace','--loop=-1','--min-frame-duration=10000','-w','-s',str(root/'trace-snapshot-'),'-S',os.environ['AUDIT_TRACE_CALL']+',999999999',os.environ['AUDIT_TRACE']] if os.environ.get('AUDIT_TRACE') else ['/usr/libexec/xscreensaver/'+name,'-window','-geometry','640x360']
    process=subprocess.Popen(command,env=env,stdout=log,stderr=log,start_new_session=True)
(root/'pid').write_text(str(process.pid))
try:
    end=time.monotonic()+float(os.environ.get('AUDIT_TIMEOUT','40'))
    while not (root/'ready').exists() and process.poll() is None and time.monotonic()<end:
        if os.environ.get('AUDIT_TRACE') and list(root.glob('trace-snapshot-*.png')):
            # retrace writes its snapshot before swapping. Give that completed
            # frame time to reach the compositor before freezing the process.
            time.sleep(.5)
            os.killpg(process.pid,signal.SIGSTOP);(root/'ready').write_text('recorded frame completed');break
        if os.environ.get('AUDIT_NO_FIXTURE') and list(root.glob('frame-*.txt')): break
        time.sleep(.05)
    assert (root/'ready').exists() or list(root.glob('frame-*.txt')), ('no completed frame',process.poll())
    time.sleep(.5)
    if os.environ.get('AUDIT_TRACE'):
        assert process.poll() is None, ('replay exited before capture', process.returncode)
        (root/'windows.txt').write_text(subprocess.check_output(['xwininfo','-root','-tree'],text=True))
        subprocess.run([sys.executable,str(Path(__file__).with_name('activate-window.py'))],check=True)
        time.sleep(.5)
    root_property=subprocess.check_output(['xprop','-root','_KDE_NET_WM_STEREO_CONTENT_SUPPORTED'],text=True)
    assert int(root_property.split('=')[-1].strip())>=3,root_property
    active=subprocess.check_output(['xprop','-root','_NET_ACTIVE_WINDOW'],text=True)
    window=re.findall(r'0x[0-9a-fA-F]+',active)[-1]
    if not reference_eye:
        declaration=subprocess.check_output(['xprop','-id',window,'_KDE_NET_WM_STEREO_CONTENT'],text=True)
        assert declaration.strip().endswith('= 3'),declaration
        (root/'declaration.txt').write_text(root_property+declaration)
    subprocess.run([os.environ.get('AUDIT_CAPTURE_TOOL','/build/capture'),str(root/'kwin.png'),'window'],check=True,timeout=30)
    a=np.array(Image.open(root/'kwin.png').convert('RGB'))
    assert a.shape==(360,640 if reference_eye else 1280,3),f'wrong composed geometry: {a.shape}'
    result=dict(size=list(a.shape),eyes_differ=float(np.any(a[:,:a.shape[1]//2]!=a[:,a.shape[1]//2:],axis=2).mean()))
    result.update(library_sha256=hashlib.sha256(Path(library).read_bytes()).hexdigest(),
                  executable_sha256=hashlib.sha256(Path('/usr/libexec/xscreensaver/'+name).read_bytes()).hexdigest(),
                  command=command,frame=int(target),separation=env.get('GL_STEREO_SEPARATION','2'))
    (root/'execution.json').write_text(json.dumps(result,indent=2)+'\n')
    if reference_eye: Image.fromarray(a).save(root/'frame.png')
    else:
        for eye,label in enumerate(('LEFT','RIGHT')): Image.fromarray(a[:,eye*a.shape[1]//2:(eye+1)*a.shape[1]//2]).save(root/(label+'.png'))
    (root/'result.json').write_text(json.dumps(result,indent=2))
finally:
    try: os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError: pass
    process.wait()
