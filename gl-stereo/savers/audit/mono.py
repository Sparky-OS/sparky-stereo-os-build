#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Compare stock and disabled-layer pixels for identical seeded input."""
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

root=Path(sys.argv[1]); root.mkdir(parents=True,exist_ok=False)
fixture=str(Path(sys.argv[2]).resolve())
library=str(Path(sys.argv[3]).resolve())
results=[]
for name in sys.argv[4:]:
    pictures=[]
    result={'id':name,'executable_sha256':hashlib.sha256(Path('/usr/libexec/xscreensaver/'+name).read_bytes()).hexdigest(),'library_sha256':hashlib.sha256(Path(library).read_bytes()).hexdigest()}
    try:
        for mode in (('left', 'right') if os.environ.get('AUDIT_REFERENCE') else ('stock', 'disabled')):
            case=root/name/mode; case.mkdir(parents=True)
            read,write=os.pipe()
            with (case/'server.log').open('w') as log:
                server=subprocess.Popen(['Xvfb','-dpi',os.environ.get('AUDIT_DPI','96'),'-displayfd',str(write),'-screen','0','1280x720x24','-ac','-noreset','-nolisten','tcp'],pass_fds=(write,),stdout=log,stderr=log)
            os.close(write)
            process=None
            try:
                display=read_display(read)
                env={k:v for k,v in os.environ.items() if not k.startswith(('GL_STEREO','AUDIT_')) and k not in ('LD_PRELOAD','DISPLAY','WAYLAND_DISPLAY','XAUTHORITY')}
                env.update(DISPLAY=display,LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='4',
                           PATH='/usr/libexec/xscreensaver:'+os.environ.get('PATH',os.defpath),
                           LD_PRELOAD=fixture+(':'+library if mode=='disabled' else ''),
                           GL_STEREO='0',AUDIT_FRAME=os.environ.get('AUDIT_TARGET','120'),AUDIT_CAPTURE=str(case/'frame.ppm'),AUDIT_READY=str(case/'ready'))
                if os.environ.get('AUDIT_STOCK_REPEAT'): env['LD_PRELOAD']=fixture
                if os.environ.get('AUDIT_REFERENCE'):
                    env.update(LD_PRELOAD=fixture+':'+library, REFERENCE_EYE=mode)
                with (case/'producer.log').open('w') as log:
                    process=subprocess.Popen(['/usr/libexec/xscreensaver/'+name,'-window','-geometry','640x360'],env=env,stdout=log,stderr=log,start_new_session=True)
                deadline=time.monotonic()+float(os.environ.get('AUDIT_TIMEOUT','30'))
                while not (case/'ready').exists() and process.poll() is None and time.monotonic()<deadline: time.sleep(.05)
                assert (case/'ready').exists(), f'{mode}: no requested frame'
                picture=Image.open(case/'frame.ppm').convert('RGB')
                picture.save(case/'frame.png'); (case/'frame.ppm').unlink()
                pictures.append(np.array(picture))
            finally:
                os.close(read)
                if process:
                    try: os.killpg(process.pid,signal.SIGKILL)
                    except ProcessLookupError: pass
                    process.wait()
                server.terminate(); server.wait(timeout=3)
        assert pictures[0].shape==pictures[1].shape
        result.update(equal=bool(np.array_equal(*pictures)),different_pixels=float(np.any(pictures[0]!=pictures[1],axis=2).mean()),stddev=float(pictures[0].std()))
    except Exception as error: result['error']=str(error)
    results.append(result)
    (root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(result,flush=True)
