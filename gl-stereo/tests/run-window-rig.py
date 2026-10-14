# SPDX-License-Identifier: GPL-2.0-or-later
"""A private compositor session for each installed window-sizing case."""
import json
from pathlib import Path
import os
import re
import signal
import subprocess
import sys
import time
import shutil

repo=Path.cwd()
name=sys.argv[1]
root=repo/'out/window-sizing'/name
root.mkdir(parents=True,exist_ok=True)
if len(sys.argv)==2:
    for old in list(root.glob('c*.png'))+[root/'run.json']:
        old.unlink(missing_ok=True)
    for directory in ('home','config','runtime'):(root/directory).mkdir(exist_ok=True)
    (root/'runtime').chmod(0o700)
    env={k:v for k,v in os.environ.items() if k not in ('DISPLAY','WAYLAND_DISPLAY','LD_PRELOAD','LIBGL_ALWAYS_SOFTWARE','GALLIUM_DRIVER')}
    env.update(HOME=str(root/'home'),XDG_CONFIG_HOME=str(root/'config'),XDG_RUNTIME_DIR=str(root/'runtime'),
               KWIN_COMPOSE='O2',KWIN_WAYLAND_NO_PERMISSION_CHECKS='1',KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1',LP_NUM_THREADS='4')
    command=['dbus-run-session','--','kwin_wayland','--virtual','--width','1280','--height','800','--xwayland',
             '--socket','gl-stereo-sizing','--no-global-shortcuts','--exit-with-session',
             f'{sys.executable} {Path(__file__).resolve()} {name} --client']
    with (root/'kwin.log').open('w') as log:
        subprocess.run(command,env=env,stdout=log,stderr=log,check=True,timeout=40)
    shutil.rmtree(root/'home'/'.cache',ignore_errors=True)
    sys.exit(0)

library=repo/('out/window-sizing/before.so' if name=='before' else 'libgl-stereo.so')
env=dict(os.environ,LD_PRELOAD=str(library),GL_STEREO='1',LIBGL_ALWAYS_SOFTWARE='1',LP_NUM_THREADS='4')
command=[str(repo/'out/window-sizing/client')]
if name=='quad':env['TEST_QUAD']='1'
if name=='future':env.update(TEST_SUPPORT_VERSION='4',TEST_RIG='1')
if name=='gears':command=['glxgears','-geometry','400x300+100+100']
with (root/'client.log').open('w') as log:
    process=subprocess.Popen(command,env=env,stdout=log,stderr=log,start_new_session=True)
start=time.monotonic(); result={'client_alive_at_end':False,'x11':{}}
try:
    for index,second in enumerate((6,7)):
        while process.poll() is None and time.monotonic()-start<second:time.sleep(.05)
        if process.poll() is not None:break
        active=subprocess.check_output(['xprop','-root','_NET_ACTIVE_WINDOW'],text=True)
        window=re.findall(r'0x[0-9a-fA-F]+',active)[-1]
        assert window!='0x0',active
        result['x11']={
            'root':subprocess.check_output(['xprop','-root','_KDE_NET_WM_STEREO_CONTENT_SUPPORTED'],text=True),
            'window':subprocess.check_output(['xprop','-id',window,'_KDE_NET_WM_STEREO_CONTENT','_KDE_NET_WM_STEREO_CONTENT_CLASS'],text=True)}
        subprocess.run([str(repo/'native/capture'),str(root/f'c{index:02}.png'),'window'],check=True,timeout=10)
    result['client_alive_at_end']=process.poll() is None
    (root/'run.json').write_text(json.dumps(result,indent=2)+'\n')
finally:
    try:os.killpg(process.pid,signal.SIGKILL)
    except ProcessLookupError:pass
    process.wait()
