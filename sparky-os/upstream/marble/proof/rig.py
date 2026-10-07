#!/usr/bin/env python3
# usage: rig.py <outdir> <clients-json> <steps-json>
# Starts headless KWin (our build), the clients, then the steps: ["wait",s] ["cap",name] ["sh",cmd] ["fi",args...]
import os, sys, json, subprocess, time, shutil
out = sys.argv[1]; clients = json.loads(sys.argv[2]); steps = json.loads(sys.argv[3])
os.makedirs(out, exist_ok=True)
rt = '/tmp/rt'; shutil.rmtree(rt, ignore_errors=True); os.makedirs(rt, mode=0o700)
env = dict(os.environ, XDG_RUNTIME_DIR=rt, HOME='/tmp/home', LANG='C.UTF-8', LC_ALL='C.UTF-8',
           KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1', KWIN_WAYLAND_NO_PERMISSION_CHECKS='1',
           SSH_ASKPASS_REQUIRE='never')
os.makedirs('/tmp/home', exist_ok=True)
W, H = os.environ.get('SCREEN', '1280x800').split('x')
kw = subprocess.Popen(['/usr/bin/kwin_wayland', '--virtual', '--xwayland', '--socket=sub', '--width', W, '--height', H],
                      env=dict(env, LIBGL_ALWAYS_SOFTWARE=os.environ.get('KWIN_SOFT', '0')) if False else env,
                      stdout=open(f'{out}/kwin.log', 'w'), stderr=subprocess.STDOUT)
for _ in range(120):
    if os.path.exists(rt + '/sub'): break
    time.sleep(.25)
time.sleep(1.5)
cenv = dict(env, WAYLAND_DISPLAY='sub', DISPLAY=':0')
procs = []
for i, c in enumerate(clients):
    e = dict(cenv); e.update(c.get('env', {}))
    procs.append(subprocess.Popen(c['argv'], env=e, stdout=open(f'{out}/client{i}.log', 'w'), stderr=subprocess.STDOUT))
for st in steps:
    if st[0] == 'wait': time.sleep(st[1])
    elif st[0] == 'cap':
        r = subprocess.run(['/w/bin/capture', 'screen', f'{out}/{st[1]}.png'], env=cenv, capture_output=True, text=True)
        open(f'{out}/{st[1]}.capture.txt', 'w').write(r.stdout + r.stderr)
    elif st[0] == 'fi':
        r = subprocess.run(['/w/bin/fakeinput'] + [str(a) for a in st[1:]], env=cenv, capture_output=True, text=True)
        open(f'{out}/fi.log', 'a').write(' '.join(map(str, st[1:])) + ' -> ' + r.stdout + r.stderr + '\n')
    elif st[0] == 'sh':
        subprocess.run(st[1], shell=True, env=cenv, stdout=open(f'{out}/sh.log', 'a'), stderr=subprocess.STDOUT)
for p in procs:
    p.terminate()
time.sleep(1)
kw.terminate()
try: kw.wait(5)
except Exception: kw.kill()
