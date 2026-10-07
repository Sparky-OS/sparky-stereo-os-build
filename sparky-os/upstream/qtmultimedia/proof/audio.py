#!/usr/bin/env python3
# usage: audio.py <outdir> <clip> : a PipeWire of its own with a null sink (SINKRATE, SINKFMT), the test player (plain.qml) playing the clip,
# then the format PipeWire negotiated for the player's stream (pw-dump) and Qt's own log of the sink format and the resampler
import os, sys, json, subprocess, time, shutil
out, clip = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
rt = '/tmp/rta'; shutil.rmtree(rt, ignore_errors=True); os.makedirs(rt, mode=0o700)
home = '/tmp/homea'; shutil.rmtree(home, ignore_errors=True); os.makedirs(home)
env = dict(os.environ, XDG_RUNTIME_DIR=rt, HOME=home, LANG='C.UTF-8', SSH_ASKPASS_REQUIRE='never')
env.pop('DISPLAY', None); env.pop('WAYLAND_DISPLAY', None)
def bg(cmd, name):
    return subprocess.Popen(cmd, env=env, stdout=open(f'{out}/{name}.log', 'w'), stderr=subprocess.STDOUT)
pw = bg(['pipewire'], 'pipewire'); time.sleep(1.5)
wp = bg(['wireplumber'], 'wireplumber'); time.sleep(1.5)
pp = bg(['pipewire-pulse'], 'pipewire-pulse'); time.sleep(1)
rate = os.environ.get('SINKRATE', '48000'); fmt = os.environ.get('SINKFMT', 'S32LE')
props = '{ factory.name=support.null-audio-sink node.name=nulldac node.description=NullDAC media.class=Audio/Sink object.linger=true audio.position=[FL FR] audio.rate=%s audio.format=%s }' % (rate, fmt)
subprocess.run(['pw-cli', 'create-node', 'adapter', props], env=env, stdout=open(f'{out}/sink.log', 'w'), stderr=subprocess.STDOUT)
time.sleep(1)
subprocess.run(['pw-metadata', '0', 'default.audio.sink', '{"name":"nulldac"}', 'Spa:String:JSON'], env=env, stdout=open(f'{out}/meta.log', 'w'), stderr=subprocess.STDOUT)
time.sleep(1)
extra = json.loads(os.environ.get('PEXTRA', '{}'))
cenv = dict(env, QT_QPA_PLATFORM='offscreen', QT_LOGGING_RULES='qt.multimedia.ffmpeg.utils.debug=true;qt.multimedia.ffmpeg.resampler.debug=true;qt.multimedia.ffmpeg.audiorenderer.debug=true', **extra)
app = subprocess.Popen(['/usr/lib/qt6/bin/qml', '/w/run/plain.qml', '--', clip], env=cenv, stdout=open(f'{out}/app.out', 'w'), stderr=subprocess.STDOUT)
time.sleep(5)
dump = subprocess.run(['pw-dump'], env=env, capture_output=True, text=True).stdout
open(f'{out}/pw-dump.json', 'w').write(dump)
for o in json.loads(dump):
    if o.get('type') != 'PipeWire:Interface:Node': continue
    info = o.get('info', {}); p = info.get('props', {})
    cls = p.get('media.class', '')
    if cls.startswith('Stream/Output/Audio') or p.get('node.name') == 'nulldac':
        fm = (info.get('params', {}).get('Format') or [{}])[0]
        print('node %s class=%s app=%s -> Format %s' % (p.get('node.name'), cls, p.get('application.name'), json.dumps(fm)))
        if 'audio.rate' in p: print('   props rate', p.get('audio.rate'), 'format', p.get('audio.format'))
app.terminate(); time.sleep(.5)
for pr in (pp, wp, pw): pr.terminate()
