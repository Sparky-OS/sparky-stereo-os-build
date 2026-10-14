#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test-only replay control: both runs receive identical recorded GL input."""
import json
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import numpy as np
from PIL import Image
root=Path(sys.argv[1]); root.mkdir(parents=True,exist_ok=False)
library=str(Path(sys.argv[2]).resolve())
results=[]
for name in sys.argv[3:]:
    case=root/name; case.mkdir(); result={'id':name,'executable_sha256':hashlib.sha256(Path('/usr/libexec/xscreensaver/'+name).read_bytes()).hexdigest(),'library_sha256':hashlib.sha256(Path(library).read_bytes()).hexdigest()}
    env={k:v for k,v in os.environ.items() if not k.startswith(('GL_STEREO','AUDIT_')) and k not in ('LD_PRELOAD','DISPLAY','WAYLAND_DISPLAY','XAUTHORITY')}
    env.update(PATH='/usr/libexec/xscreensaver:'+os.environ.get('PATH',os.defpath),LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='4')
    trace=case/'input.trace'
    try:
        record_env=dict(env)
        if os.environ.get('AUDIT_RECORD_FIXTURE'):
            record_env.update(LD_PRELOAD=os.environ['AUDIT_RECORD_FIXTURE'],AUDIT_FRAME='1000000000',AUDIT_TEXT=os.environ['AUDIT_RECORD_TEXT'])
        with (case/'record.log').open('w') as log:
            run=subprocess.run(['xvfb-run','-a','timeout','--signal=TERM','--kill-after=3','12','apitrace','trace','--api=egl','-o',str(trace),'/usr/libexec/xscreensaver/'+name,'-window','-geometry','640x360'],env=record_env,stdout=log,stderr=log,timeout=30)
        assert run.returncode in (0,124),run.returncode
        calls=subprocess.check_output(['apitrace','dump','--calls=frame',str(trace)],text=True)
        numbers=re.findall(r'^(\d+) ',calls,re.M)
        assert len(numbers)>2,'no completed frames'
        frame=numbers[-2]  # Ignore any final call interrupted during shutdown.
        result.update(completed_frames=len(numbers),call=int(frame),trace_sha256=hashlib.sha256(trace.read_bytes()).hexdigest())
        pictures=[]
        for mode in ('stock','disabled'):
            output=case/mode; output.mkdir()
            run_env=dict(env,GL_STEREO='0')
            if mode=='disabled':run_env['LD_PRELOAD']=library
            with (case/(mode+'.log')).open('w') as log:
                subprocess.run(['xvfb-run','-a','glretrace','-s',str(output/'frame-'),'-S',frame,str(trace)],env=run_env,stdout=log,stderr=log,check=True,timeout=120)
            picture=next(output.glob('*.png'))
            pictures.append(np.array(Image.open(picture).convert('RGB')))
        assert pictures[0].shape==pictures[1].shape
        result.update(equal=bool(np.array_equal(*pictures)),different_pixels=float(np.any(pictures[0]!=pictures[1],axis=2).mean()),stddev=float(pictures[0].std()))
        assert result['equal'] and result['stddev']>1,'pixels differ or scene is empty'
        result['passed']=True
    except Exception as error:result.update(passed=False,error=str(error))
    results.append(result); (root/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(result,flush=True)
