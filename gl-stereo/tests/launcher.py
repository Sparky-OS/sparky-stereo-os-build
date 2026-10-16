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
# OpenGL on NVIDIA: zink's environment lists Mesa's EGL vendor first and
# NVIDIA's second, which NVIDIA's Vulkan driver needs, and is never set by hand.
import tempfile
with tempfile.TemporaryDirectory() as vendors:
    globals_ = module['zink_environment'].__globals__
    globals_['EGL_VENDORS'] = Path(vendors)
    (Path(vendors)/'50_mesa.json').write_text('{}')
    zink = {}
    assert not module['zink_environment'](zink) and zink == {}
    (Path(vendors)/'10_nvidia.json').write_text('{}')
    assert module['zink_environment'](zink)
    assert zink['__EGL_VENDOR_LIBRARY_FILENAMES'] == f'{vendors}/50_mesa.json:{vendors}/10_nvidia.json'
    assert zink['__GLX_VENDOR_LIBRARY_NAME'] == 'mesa' and zink['MESA_LOADER_DRIVER_OVERRIDE'] == 'zink'
    assert zink['LIBGL_KOPPER_DISABLE'] == '1' and zink['GL_STEREO_DRIVER_VIEWS'] == '1'
session = dict(os.environ, SPARKY_STEREO_OPENGL='zink', MESA_LOADER_DRIVER_OVERRIDE='zink', LIBGL_KOPPER_DISABLE='1', OTHER='kept')
assert module['without_session_zink'](session) == dict(os.environ, OTHER='kept')
own = dict(os.environ, MESA_LOADER_DRIVER_OVERRIDE='radeonsi')
assert module['without_session_zink'](own) == own
# Here Mesa serves the display, so neither choice changes the program's OpenGL.
assert not module['nvidia_opengl_serves'](dict(os.environ))
script = "import os,json;print(json.dumps({k:v for k,v in os.environ.items() if k in ('MESA_LOADER_DRIVER_OVERRIDE','__EGL_VENDOR_LIBRARY_FILENAMES','GL_STEREO_DRIVER_VIEWS')}))"
for choice in ('zink', 'nvidia'):
    value = json.loads(subprocess.check_output(['./gl-stereo-run','--nvidia-opengl',choice,'--',sys.executable,'-c',script]))
    assert value == {'GL_STEREO_DRIVER_VIEWS': '1'}, (choice, value)
print('PASS: Enable 3D, per-eye resolution validation, exact Display settings command and the OpenGL choice on NVIDIA')
