# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import subprocess
import sys
p = Path('out/launcher')
p.mkdir(parents=True, exist_ok=True)
script = "import os,json;print(json.dumps({k:v for k,v in os.environ.items() if k.startswith('GL_STEREO') or k=='LD_PRELOAD'}))"
for on in ('on', 'off'):
    value = json.loads(subprocess.check_output(['./gl-stereo-run','--enable-3d',on,'--render-resolution','800x600','--',sys.executable,'-c',script]))
    assert value['GL_STEREO'] == ('1' if on == 'on' else '0')
    if on == 'on':
        assert value['GL_STEREO_RENDER_RESOLUTION'] == '800x600'
        assert 'libgl-stereo.so' in value['LD_PRELOAD']
    else:
        assert 'GL_STEREO_RENDER_RESOLUTION' not in value
for bad in ('0x200', 'nan', '9000x100', '100x100;false'):
    result = subprocess.run(['./gl-stereo-run','--render-resolution',bad,'--','true'],capture_output=True)
    assert result.returncode != 0
stub = p/'kcmshell6'
stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "'+str(p.resolve()/'display-args')+'"\n')
stub.chmod(0o755)
env = dict(os.environ, PATH=str(p.resolve())+':'+os.environ['PATH'])
# Load the module to await only the stub child, never a desktop process.
import runpy
module = runpy.run_path('./gl-stereo-run', run_name='launcher_test')
original = os.environ['PATH']
os.environ['PATH'] = env['PATH']
module['display_settings']()
os.wait()
os.environ['PATH'] = original
assert (p/'display-args').read_text() == 'kcm_kscreen\n'
print('PASS: Enable 3D, per-eye resolution validation and exact Display settings command')
