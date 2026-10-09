#!/usr/bin/python3
"""Run under dbus-run-session; never touches the desktop bus or user config."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import wave

out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
env = dict(os.environ)
for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'XAUTHORITY'):
    env.pop(key, None)
env.update(XDG_CONFIG_HOME=str(out / 'config'), XDG_DATA_HOME=str(out / 'data'),
           XDG_CACHE_HOME=str(out / 'cache'))
procs = []
results = {}

def start(binary, name, *args):
    log = (out / (name + '.log')).open('w')
    p = subprocess.Popen([binary, '-vv', '-I', 'dummy', '--aout=dummy',
                          '--no-media-library', '--no-metadata-network-access', *args],
                         env=env, stdout=log, stderr=subprocess.STDOUT)
    log.close()
    procs.append(p)
    time.sleep(1)
    results[name] = {'pid': p.pid, 'exit': p.poll()}
    return p

def owner(name):
    return subprocess.run(['busctl', '--user', 'call', 'org.freedesktop.DBus',
                           '/org/freedesktop/DBus', 'org.freedesktop.DBus',
                           'GetConnectionUnixProcessID', 's', name],
                          text=True, capture_output=True).stdout.strip()

try:
    first = start('/usr/bin/vlc-stereo', 'menu-first', '--started-from-file')
    results['first_owner'] = owner('org.mpris.MediaPlayer2.vlc-stereo')
    if first.poll() is None:
        second = start('/usr/bin/vlc-stereo', 'menu-second', '--started-from-file')
        results['second_kept_first'] = owner('org.mpris.MediaPlayer2.vlc-stereo') == 'u ' + str(first.pid)
        first.terminate()
        first.wait(timeout=5)
    stock = start('/usr/bin/vlc', 'ordinary-vlc', '--no-one-instance')
    stereo = start('/usr/bin/vlc-stereo', 'beside-ordinary', '--started-from-file')
    results['stock_owner'] = owner('org.mpris.MediaPlayer2.vlc')
    results['stereo_owner'] = owner('org.mpris.MediaPlayer2.vlc-stereo')
    # A local playlist item must be forwarded to Stereo, leaving stock VLC empty.
    if stereo.poll() is None:
        selection = out / 'selection.wav'
        with wave.open(str(selection), 'wb') as wav:
            wav.setparams((1, 2, 8000, 0, 'NONE', 'not compressed'))
            wav.writeframes(b'\0\0' * 8000 * 30)
        forwarded = start('/usr/bin/vlc-stereo', 'file-forward', '--started-from-file', str(selection))
        for name, bus in [('stereo', 'org.mpris.MediaPlayer2.vlc-stereo'), ('stock', 'org.mpris.MediaPlayer2.vlc')]:
            r = subprocess.run(['busctl', '--user', 'get-property', bus, '/org/mpris/MediaPlayer2',
                                'org.mpris.MediaPlayer2.TrackList', 'Tracks'], text=True, capture_output=True)
            results[name + '_tracks'] = r.stdout.strip()
finally:
    for p in procs:
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
results['passed'] = (
    results['menu-first']['exit'] is None
    and results.get('first_owner') == 'u ' + str(results['menu-first']['pid'])
    and results.get('menu-second', {}).get('exit') == 0
    and results.get('second_kept_first') is True
    and results['beside-ordinary']['exit'] is None
    and results.get('stock_owner') == 'u ' + str(results['ordinary-vlc']['pid'])
    and results.get('stereo_owner') == 'u ' + str(results['beside-ordinary']['pid'])
    and results.get('file-forward', {}).get('exit') == 0
    and results.get('stereo_tracks', '').startswith('ao 1 ')
    and results.get('stock_tracks') == 'ao 0'
)
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results, indent=2))
sys.exit(0 if results['passed'] else 1)
