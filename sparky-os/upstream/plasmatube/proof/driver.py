#!/usr/bin/env python3
# usage: driver.py <outdir> <video-id> [steps-json]    (inside the run container; /w = work dir, /p = shared capture tools)
# Starts the local mock Invidious, writes PlasmaTube's state (one Invidious source on the mock), starts headless KWin and PlasmaTube
# with a youtube.com/watch?v=<id> link, then runs steps: ["wait",s] ["cap",name] ["fi",x,y,"click"] ["sh",cmd]
import os, sys, json, subprocess, time, shutil
out = sys.argv[1]; vid = sys.argv[2]
steps = json.loads(sys.argv[3]) if len(sys.argv) > 3 else [['wait', 14], ['cap', 'c1']]
os.makedirs(out, exist_ok=True)
rt = '/tmp/rt'; shutil.rmtree(rt, ignore_errors=True); os.makedirs(rt, mode=0o700)
home = '/tmp/home'; shutil.rmtree(home, ignore_errors=True); os.makedirs(home + '/.local/state', exist_ok=True)
open(home + '/.local/state/plasmatubestaterc', 'w').write('[General]\nLastSource={11111111-2222-3333-4444-555555555555}\n\n[source-{11111111-2222-3333-4444-555555555555}]\nurl=127.0.0.1:8099\nprotocol=http\ntype=0\n')
env = dict(os.environ, XDG_RUNTIME_DIR=rt, HOME=home, XDG_STATE_HOME=home + '/.local/state', LANG='C.UTF-8', LC_ALL='C.UTF-8',
           KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1', KWIN_WAYLAND_NO_PERMISSION_CHECKS='1', SSH_ASKPASS_REQUIRE='never')
env.pop('DISPLAY', None)
mock = subprocess.Popen(['python3', '/w/run/mock.py', '8099', '/w/clips', os.environ.get('VIDEOS', '/w/run/videos.json')],
                        env=dict(env, MOCK_LOG=out + '/mock.log'), stdout=open(out + '/mock.out', 'w'), stderr=subprocess.STDOUT)
W, H = os.environ.get('SCREEN', '1280x800').split('x')
kw = subprocess.Popen(['/usr/bin/kwin_wayland', '--virtual', '--xwayland', '--socket=sub', '--width', W, '--height', H],
                      env=env, stdout=open(f'{out}/kwin.log', 'w'), stderr=subprocess.STDOUT)
for _ in range(120):
    if os.path.exists(rt + '/sub'): break
    time.sleep(.25)
time.sleep(1.5)
cenv = dict(env, WAYLAND_DISPLAY='sub', QT_QPA_PLATFORM='wayland')
pt = subprocess.Popen([os.environ.get('PTBIN', 'plasmatube'), 'https://www.youtube.com/watch?v=' + vid], env=dict(cenv, **dict({'WAYLAND_DEBUG': '1', 'QT_LOGGING_RULES': '*.debug=false'}, **json.loads(os.environ.get('PTEXTRA', '{}')))),
                      stdout=open(f'{out}/client0.out', 'w'), stderr=open(f'{out}/client0.log', 'w'))
for st in steps:
    if st[0] == 'wait': time.sleep(st[1])
    elif st[0] == 'cap':
        e = dict(cenv, QT_CAPTURE_SCREEN='1', QT_CAPTURE_PNG=f'{out}/{st[1]}.png')
        r = subprocess.run(['/p/qt-capture', '', 'red,blue', 'nolabel'], env=e, capture_output=True, text=True)
        open(f'{out}/{st[1]}.capture.txt', 'w').write(r.stdout + r.stderr)
    elif st[0] == 'fi':
        subprocess.run(['/w/run/tools/fi', str(st[1]), str(st[2])] + st[3:], env=cenv, stdout=open(f'{out}/sh.log', 'a'), stderr=subprocess.STDOUT)
    elif st[0] == 'sh':
        subprocess.run(st[1], shell=True, env=cenv, stdout=open(f'{out}/sh.log', 'a'), stderr=subprocess.STDOUT)
pt.terminate(); time.sleep(1)
for p in (kw, mock):
    p.terminate()
    try: p.wait(5)
    except Exception: p.kill()
