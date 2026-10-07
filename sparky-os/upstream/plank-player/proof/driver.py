#!/usr/bin/env python3
# usage: driver.py <outdir> <clip file> [steps-json]    (inside the run container; /w = work dir, /p = shared capture tools)
# Starts headless KWin and Plank Player with the clip as its argument, then runs the steps:
# ["wait",s] ["cap",name] ["fk",linux key code,count] (a key press through KWin's fake input) ["sh",cmd]
import os, sys, json, subprocess, time, shutil
out = sys.argv[1]; clip = sys.argv[2]
steps = json.loads(sys.argv[3]) if len(sys.argv) > 3 else [['wait', 8], ['cap', 'c1']]
os.makedirs(out, exist_ok=True)
rt = '/tmp/rt'; shutil.rmtree(rt, ignore_errors=True); os.makedirs(rt, mode=0o700)
home = '/tmp/home'; shutil.rmtree(home, ignore_errors=True); os.makedirs(home, exist_ok=True)
env = dict(os.environ, XDG_RUNTIME_DIR=rt, HOME=home, LANG='C.UTF-8', LC_ALL='C.UTF-8',
           KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1', KWIN_WAYLAND_NO_PERMISSION_CHECKS='1', SSH_ASKPASS_REQUIRE='never')
env.pop('DISPLAY', None)
W, H = os.environ.get('SCREEN', '1280x800').split('x')
kw = subprocess.Popen(['/usr/bin/kwin_wayland', '--virtual', '--socket=sub', '--width', W, '--height', H],
                      env=env, stdout=open(f'{out}/kwin.log', 'w'), stderr=subprocess.STDOUT)
for _ in range(120):
    if os.path.exists(rt + '/sub'): break
    time.sleep(.25)
time.sleep(1.5)
cenv = dict(env, WAYLAND_DISPLAY='sub', QT_QPA_PLATFORM='wayland')
pt = subprocess.Popen([os.environ.get('PBIN', 'plank-player'), '/w/clips/' + clip],
                      env=dict(cenv, **dict({'WAYLAND_DEBUG': '1', 'QT_LOGGING_RULES': '*.debug=false;qt.qml.*=false'}, **json.loads(os.environ.get('PEXTRA', '{}')))),
                      stdout=open(f'{out}/client0.out', 'w'), stderr=open(f'{out}/client0.log', 'w'))
for st in steps:
    if st[0] == 'wait': time.sleep(st[1])
    elif st[0] == 'cap':
        e = dict(cenv, QT_CAPTURE_SCREEN='1', QT_CAPTURE_PNG=f'{out}/{st[1]}.png')
        r = subprocess.run(['/p/qt-capture', '', 'red,blue', 'nolabel'], env=e, capture_output=True, text=True)
        open(f'{out}/{st[1]}.capture.txt', 'w').write(r.stdout + r.stderr)
    elif st[0] == 'fk':
        subprocess.run(['/w/run/tools/fk'] + [str(x) for x in st[1:]], env=cenv, stdout=open(f'{out}/sh.log', 'a'), stderr=subprocess.STDOUT)
    elif st[0] == 'sh':
        subprocess.run(st[1], shell=True, env=cenv, stdout=open(f'{out}/sh.log', 'a'), stderr=subprocess.STDOUT)
pt.terminate(); time.sleep(1)
kw.terminate()
try: kw.wait(5)
except Exception: kw.kill()
