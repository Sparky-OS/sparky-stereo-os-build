#!/usr/bin/env python3
# In the container, as an ordinary user, under dbus-run-session.
# usage: drv.py <outdir> <json: {"mpv": [args...], "caps": [times], "screen": "1280x800", "tail": seconds, "pre": [argv to run before mpv]}>
# Headless KWin (the packaged one), mpv started on its Wayland socket with WAYLAND_DEBUG=client, captures by KWin's ScreenShot2.
import os, sys, json, subprocess, time, shutil, select, signal
import dbus
from PIL import Image
out = sys.argv[1]; cfg = json.loads(sys.argv[2]); os.makedirs(out, exist_ok=True)
rt = '/tmp/rt'; shutil.rmtree(rt, ignore_errors=True); os.makedirs(rt, mode=0o700)
env = dict(os.environ, XDG_RUNTIME_DIR=rt, HOME='/tmp/home', LANG='C.UTF-8', KWIN_SCREENSHOT_NO_PERMISSION_CHECKS='1')
os.makedirs('/tmp/home', exist_ok=True)
W, H = cfg.get('screen', '1280x800').split('x')
kw = subprocess.Popen(['kwin_wayland', '--virtual', '--xwayland', '--socket=sub', '--width', W, '--height', H], env=env,
                      stdout=open(out + '/kwin.log', 'w'), stderr=subprocess.STDOUT)
for _ in range(120):
    if os.path.exists(rt + '/sub'): break
    time.sleep(.25)
time.sleep(1.5)
cenv = dict(env, WAYLAND_DISPLAY='sub', DISPLAY=':0', WAYLAND_DEBUG='client')
bus = dbus.SessionBus()

def capture_once(path):
    r, w = os.pipe()
    iface = bus.get_object('org.kde.KWin.ScreenShot2', '/org/kde/KWin/ScreenShot2')
    opts = {'include-decoration': dbus.Boolean(False), 'include-shadow': dbus.Boolean(False), 'include-cursor': dbus.Boolean(False), 'hide-caller-windows': dbus.Boolean(False)}
    md = iface.CaptureActiveScreen(opts, dbus.types.UnixFd(w), dbus_interface='org.kde.KWin.ScreenShot2')
    os.close(w)
    width, height, stride = int(md['width']), int(md['height']), int(md['stride'])
    need = stride * height; data = bytearray()
    while len(data) < need:
        if not select.select([r], [], [], 5)[0]: raise RuntimeError('capture timeout')
        c = os.read(r, need - len(data))
        if not c: break
        data.extend(c)
    os.close(r)
    Image.frombytes('RGBA', (width, height), bytes(data), 'raw', 'BGRA', stride, 1).convert('RGB').save(path)
    return {k: str(v) for k, v in md.items()}

def capture(path):
    # KWin's ScreenShot2 sometimes closes the pipe early under load ("not enough image data"); a failed capture is
    # a harness failure, not a result: ask again (up to 4 tries) and record how many retries a capture needed.
    last = None
    for attempt in range(4):
        try:
            md = capture_once(path); md['retries'] = str(attempt); return md
        except Exception as e:
            last = e; time.sleep(0.4)
    raise last

def tod_now():
    t = time.time(); lt = time.localtime(t)
    return lt.tm_hour * 3600 + lt.tm_min * 60 + lt.tm_sec + (t - int(t))

mpvlog = open(out + '/mpv.log', 'w')
t0 = time.monotonic(); t0_tod = tod_now()
mpv = subprocess.Popen([cfg.get('bin', 'mpv'), '--no-config', '--no-audio', '--no-terminal' if False else '--msg-level=all=v'] + cfg['mpv'], env=cenv, stdout=mpvlog, stderr=subprocess.STDOUT)
caps = []
import socket
def ipc(cmd):
    c = socket.socket(socket.AF_UNIX); c.connect('/tmp/mpv.sock'); c.sendall((json.dumps({'command': cmd}) + '\n').encode()); c.settimeout(3)
    try: r = c.recv(65536)
    except Exception: r = b''
    c.close(); return r
if 'steps' in cfg:
    for st in cfg['steps']:
        if st[0] == 'wait': time.sleep(st[1])
        elif st[0] == 'ipc': ipc(st[1])
        elif st[0] == 'get': open(out + '/get.log', 'a').write('%s -> %s\n' % (st[1], ipc(['get_property', st[1]]).decode(errors='replace')[:6000]))
        elif st[0] == 'cap':
            tm = time.monotonic(); tod = tod_now(); i = len(caps)
            md = capture('%s/c%02d.png' % (out, i))
            caps.append({'i': i, 'tod': tod, 'mono_ms': round(tm * 1000, 1), 'stereo': md.get('stereo', ''), 'w': md.get('width'), 'h': md.get('height'), 'retries': md.get('retries', '0')})
    cfg['caps'] = [0]
for i, t in enumerate(cfg['caps'] if 'steps' not in cfg else []):
    d = t0 + t - time.monotonic()
    if d > 0: time.sleep(d)
    tm = time.monotonic(); tod = tod_now()
    md = capture('%s/c%02d.png' % (out, i))
    caps.append({'i': i, 'tod': tod, 'mono_ms': round(tm * 1000, 1), 'stereo': md.get('stereo', ''), 'w': md.get('width'), 'h': md.get('height'), 'retries': md.get('retries', '0')})
d = t0 + cfg.get('end', cfg['caps'][-1] + 1) - time.monotonic() if 'steps' not in cfg else 0
if d > 0: time.sleep(d)
kill_ms = round(time.monotonic() * 1000, 1); kill_tod = tod_now()
alive = mpv.poll() is None
mpv_rc = None if alive else mpv.returncode
mpv.send_signal(signal.SIGTERM)
try: mpv.wait(timeout=8)
except subprocess.TimeoutExpired: mpv.kill()
json.dump({'caps': caps, 'kill_ms': kill_ms, 'kill_tod': kill_tod, 't0_tod': t0_tod, 'mpv_alive_at_kill': alive, 'mpv_returncode': mpv_rc, 't0_ms': round(t0 * 1000, 1)}, open(out + '/caps.json', 'w'))
kw.terminate()
try: kw.wait(timeout=8)
except subprocess.TimeoutExpired: kw.kill()
