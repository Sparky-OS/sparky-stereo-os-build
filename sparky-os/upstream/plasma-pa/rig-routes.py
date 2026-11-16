#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Content and ownership checks through the actual KDED routing interface."""
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import wave
from gi.repository import Gio, GLib

work = Path(sys.argv[1])
work.mkdir(parents=True, exist_ok=True)
rate=int(os.environ.get('PA19_RATE','48000'))
native=os.environ.get('PA19_NATIVE')=='1'
os.environ.update(HOME=str(work/'home'), XDG_RUNTIME_DIR=str(work/'run'),
                  XDG_CONFIG_HOME=str(work/'home/config'), QT_QPA_PLATFORM='offscreen',
                  LC_ALL='C.UTF-8', QT_PLUGIN_PATH='/opt/order19b/lib/x86_64-linux-gnu/plugins',
                  LD_LIBRARY_PATH='/opt/order19b/lib/x86_64-linux-gnu',
                  XDG_DATA_DIRS='/opt/order19b/share:/usr/share')
if native:
    os.environ['LD_LIBRARY_PATH']+=':/work19/native/root/usr/lib/x86_64-linux-gnu/pulseaudio:/work19/native/root/usr/lib/pulse-17.0+dfsg1/modules'
for p in ('home', 'home/config', 'run'):
    (work/p).mkdir(mode=0o700, parents=True, exist_ok=True)
children, logs, files = [], [], []
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus',
              'UpdateActivationEnvironment',GLib.Variant('(a{ss})',({k:v for k,v in os.environ.items()
              if k.startswith(('QT_', 'QML_', 'XDG_', 'LD_LIBRARY_PATH', 'LC_ALL', 'HOME'))},)),
              None,Gio.DBusCallFlags.NONE,10000,None)

def spawn(args, stdout=None):
    log = open(work/(Path(args[0]).name+str(len(children))+'.log'), 'w')
    logs.append(log)
    p = subprocess.Popen(args, stdout=stdout or log, stderr=log)
    children.append(p)
    return p

def pactl(*args):
    return subprocess.check_output(['pactl', *args], text=True)

def wait_for(fn, label):
    for _ in range(120):
        try:
            result = fn()
            if result: return result
        except (GLib.Error, subprocess.CalledProcessError): pass
        time.sleep(.1)
    raise AssertionError(label)

def call(method, args=None):
    return bus.call_sync('org.kde.kded6', '/org/kde/plasma/AudioRoutes',
                         'org.kde.plasma.AudioRoutes', method, args,
                         None, Gio.DBusCallFlags.NONE, 10000, None).unpack()

def snapshot(): return json.loads(call('snapshot')[0])
def listen(enabled, output='out-a'):
    call('setListen', GLib.Variant('(ssb)', ('mic-a', output, enabled)))
def combined(enabled):
    call('setCombined', GLib.Variant('(ssb)', ('mic-a', 'out-a', enabled)))
def rows(kind): return json.loads(pactl('-f','json','list',kind))
def graph(name):
    data=pactl('-f','json','list') if native else subprocess.check_output(['pw-dump'],text=True)
    (work/(name+'.json')).write_text(data)
def owned():
    return [r for kind in ('sink-inputs','source-outputs','sources') for r in rows(kind)
            if r.get('name','').startswith('plasma_pa_combined') or
            r['properties'].get('node.name','').startswith('plasma-pa-') or 'plasma.pa.owner' in r['properties']]

def record(device, name):
    f = open(work/(name+'.f32'), 'wb'); files.append(f)
    return spawn(['parec','--raw','--format=float32le','--rate='+str(rate),'--channels=2','--device='+device], f)

def amplitudes(name):
    data = (work/(name+'.f32')).read_bytes()
    samples = struct.unpack('<'+'f'*(len(data)//4), data)[::2]
    # Seek a full one-second signal window; retain a silent control's middle.
    start = next((i for i,x in enumerate(samples) if abs(x)>.03), 0)+rate//20
    window = samples[start:start+rate]
    assert len(window)==rate, (name,len(samples))
    result = {str(freq): 2*abs(sum(x*complex(math.cos(2*math.pi*freq*i/rate),
                  -math.sin(2*math.pi*freq*i/rate)) for i,x in enumerate(window)))/len(window)
              for freq in (440,880,1333)}
    print(name, result, flush=True)
    return result

try:
    if native:
        spawn(['/work19/native/root/usr/bin/pulseaudio','-n','--daemonize=no','--exit-idle-time=-1','--use-pid-file=no',
               '--dl-search-path=/work19/native/root/usr/lib/pulse-17.0+dfsg1/modules','-L','module-native-protocol-unix'])
    else:
        spawn(['pipewire']); wait_for(lambda: (work/'run/pipewire-0').exists(),'PipeWire')
        spawn(['wireplumber']); spawn(['pipewire-pulse'])
    wait_for(lambda: bool(pactl('info')),'Pulse server')
    for target in ('out-a','out-b','mic-bus'):
        pactl('load-module','module-null-sink','sink_name='+target,'rate='+str(rate))
    mic = pactl('load-module','module-remap-source','master=mic-bus.monitor','source_name=mic-a').strip()
    spawn(['kded6'])
    wait_for(lambda: snapshot(),'routing service')
    assert not snapshot()['combined']['enabled'] and not snapshot()['listen']
    assert not owned(), owned()
    if rate==96000 and not native:
        spawn(['paplay','--raw','--rate=96000','--format=float32le','--channels=2','--device=mic-bus','/dev/zero'])
        time.sleep(.8)
    listen(True)
    wait_for(lambda: snapshot()['listen']['mic-a']['running'], 'Listen becomes active')
    graph('idle-listen-graph')
    if not native:
        idle=json.loads((work/'idle-listen-graph.json').read_text())
        route_nodes=[n for n in idle if n.get('info',{}).get('props',{}).get('node.name','').startswith('plasma-pa-Listen-')]
        assert len(route_nodes)==2 and all(n['info']['state']=='running' for n in route_nodes), [(n['info']['props']['node.name'],n['info']['state']) for n in route_nodes]
    combined(True)
    wait_for(lambda: snapshot()['combined']['running'], 'Combined becomes active')
    for freq in (440,880):
        with wave.open(str(work/f'{freq}.wav'),'w') as f:
            f.setparams((2,2,rate,0,'NONE','not compressed'))
            f.writeframes(b''.join(struct.pack('<hh',*(int(3000*math.sin(2*math.pi*freq*i/rate)),)*2) for i in range(rate*4)))
    recorders = [record(device,name) for device,name in
                 [('mic-a','ordinary-mic'),('out-a.monitor','listen-output'),
                  ('out-b.monitor','negative-output'),('plasma_pa_combined','combined')]]
    time.sleep(.6)
    players=[spawn(['paplay','--device='+target,str(work/f'{freq}.wav')])
             for target,freq in [('mic-bus',440),('out-a',880)]]
    time.sleep(.5)
    graph('active-graph')
    (work/'active-pulse.json').write_text(json.dumps({kind:rows(kind) for kind in ('sources','sinks','source-outputs','sink-inputs')},indent=2))
    for p in players: assert p.wait(timeout=12)==0
    time.sleep(.2)
    for p in recorders: p.terminate(); p.wait(timeout=5)
    for f in files: f.close()
    results={name:amplitudes(name) for name in ('ordinary-mic','listen-output','negative-output','combined')}
    assert results['ordinary-mic']['440']>.06 and results['ordinary-mic']['880']<.001
    assert results['listen-output']['440']>.06 and results['listen-output']['880']>.06
    assert max(results['negative-output'].values())<.001
    assert results['combined']['440']>.12 and results['combined']['880']>.06
    # The combined source includes the chosen output's mix; that output also
    # contains the separately enabled Listen route, so its mic tone is doubled.
    (work/'content.json').write_text(json.dumps(results,indent=2)+'\n')
    listen(False); combined(False)
    wait_for(lambda: not owned(),'disable removes all owned nodes')
    for _ in range(3):
        listen(True); wait_for(lambda: snapshot()['listen']['mic-a']['running'],'repeat enable')
        listen(False); wait_for(lambda: not owned(),'repeat disable')
    listen(True)
    wait_for(lambda: snapshot()['listen']['mic-a']['running'],'before missing input')
    pactl('unload-module',mic)
    wait_for(lambda: snapshot()['listen']['mic-a']['reason']==2,'missing input reported')
    wait_for(lambda: not owned(),'missing input removes route')
    pactl('load-module','module-remap-source','master=mic-bus.monitor','source_name=mic-a')
    wait_for(lambda: snapshot()['listen']['mic-a']['running'],'same input resumes')
    listen(True,'missing-output')
    assert snapshot()['listen']['mic-a']['reason']==3
    listen(False)
    call('setCombined',GLib.Variant('(ssb)',('plasma_pa_combined','out-a',True)))
    assert snapshot()['combined']['reason']==8
    combined(False)
    wait_for(lambda: not owned(),'final clean graph')
    (work/'snapshot.json').write_text(json.dumps(snapshot(),indent=2)+'\n')
    graph('graph')
    print('PASS: default off, real content, simultaneous recording, negative output, repeat, missing target/resume, feedback, teardown',flush=True)
finally:
    for p in reversed(children):
        if p.poll() is None: p.terminate()
    for p in children:
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
    for f in files+logs: f.close()
