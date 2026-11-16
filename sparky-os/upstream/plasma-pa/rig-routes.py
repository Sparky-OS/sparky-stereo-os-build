#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Content and ownership checks through the actual KDED routing interface."""
import json
import hashlib
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
prefix='/usr' if os.environ.get('PA19_INSTALLED')=='1' else '/opt/order19b'
rate=int(os.environ.get('PA19_RATE','48000'))
native=os.environ.get('PA19_NATIVE')=='1'
channels=int(os.environ.get('PA19_CHANNELS','2'))
os.environ.update(HOME=str(work/'home'), XDG_RUNTIME_DIR=str(work/'run'),
                  XDG_CONFIG_HOME=str(work/'home/config'), QT_QPA_PLATFORM='offscreen',
                  LC_ALL='C.UTF-8', QT_PLUGIN_PATH=prefix+'/lib/x86_64-linux-gnu/plugins',
                  LD_LIBRARY_PATH=prefix+'/lib/x86_64-linux-gnu',
                  XDG_DATA_DIRS=prefix+'/share:/usr/share')
if os.environ.get('PA19_INSTALLED')=='1':
    for key in ('QT_PLUGIN_PATH','QML_IMPORT_PATH','LD_LIBRARY_PATH'): os.environ.pop(key,None)
if native:
    os.environ['LD_LIBRARY_PATH']=os.environ.get('LD_LIBRARY_PATH','')+':/work19/native/root/usr/lib/x86_64-linux-gnu/pulseaudio:/work19/native/root/usr/lib/pulse-17.0+dfsg1/modules'
for p in ('home', 'home/config', 'run'):
    (work/p).mkdir(mode=0o700, parents=True, exist_ok=True)
person_files=[]
for relative in ('pipewire/pipewire.conf.d/99-person.conf','pipewire/client.conf.d/99-person.conf',
                 'wireplumber/wireplumber.conf.d/99-person.conf','pulse/default.pa'):
    p=work/'home/config'/relative; p.parent.mkdir(parents=True,exist_ok=True)
    content='# A person owns this file.\n'
    if relative.startswith('pipewire/'): content+='context.properties = {}\n'
    if relative.startswith('wireplumber/'): content+='wireplumber.settings = {}\n'
    p.write_text(content); person_files.append(p)
person_hashes={str(p.relative_to(work)):hashlib.sha256(p.read_bytes()).hexdigest() for p in person_files}
children, logs, files = [], [], []
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus',
              'UpdateActivationEnvironment',GLib.Variant('(a{ss})',({k:v for k,v in os.environ.items()
              if k.startswith(('QT_', 'QML_', 'XDG_', 'LD_LIBRARY_PATH', 'LC_ALL', 'HOME'))},)),
              None,Gio.DBusCallFlags.NONE,10000,None)

def spawn(args, stdout=None, env=None):
    log = open(work/(Path(args[0]).name+str(len(children))+'.log'), 'w')
    logs.append(log)
    p = subprocess.Popen(args, stdout=stdout or log, stderr=log, env=env)
    children.append(p)
    return p

def pactl(*args):
    return subprocess.check_output(['pactl', *args], text=True)
def create_mic(name):
    extra=['channels=1','channel_map=mono','master_channel_map=front-left','remix=false'] if channels==1 else []
    return pactl('load-module','module-remap-source','master=mic-bus.monitor','source_name='+name,*extra).strip()

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
def service_ready():
    return bus.call_sync('org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus',
                         'NameHasOwner',GLib.Variant('(s)',('org.kde.kded6',)),None,
                         Gio.DBusCallFlags.NONE,10000,None).unpack()[0]
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
    def amplitude(freq):
        return 2*abs(sum(x*complex(math.cos(2*math.pi*freq*i/rate),
                   -math.sin(2*math.pi*freq*i/rate)) for i,x in enumerate(window)))/len(window)
    # PulseAudio's loopback compensates independent null-device clocks by
    # adjusting its rate. Detect the known tone within a stated 0.5% band.
    result={str(freq): math.sqrt(sum(amplitude(f)**2 for f in range(freq-max(3,freq//200),freq+max(3,freq//200)+1)))
            if native else amplitude(freq) for freq in (440,880,1333)}
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
    mic = create_mic('mic-a')
    wait_for(lambda: pactl('get-default-source').strip()=='mic-a','WirePlumber settles the initial default input')
    defaults={kind:pactl('get-default-'+kind).strip() for kind in ('source','sink')}
    failure_mode=os.environ.get('PA19_FAILURE_MODE','')
    service_env=dict(os.environ)
    if failure_mode:
        tools=work/'tools'; tools.mkdir()
        service_env['PATH']=str(tools)
        if failure_mode=='exit':
            for helper in ('pw-loopback','pw-cli'):
                p=tools/helper; p.write_text('#!/bin/sh\nexit 42\n'); p.chmod(0o755)
    service=spawn(['/usr/bin/kded6'],env=service_env)
    wait_for(service_ready,'KDED name')
    wait_for(lambda: snapshot(),'routing service')
    assert not snapshot()['combined']['enabled'] and not snapshot()['listen']
    assert not owned(), owned()
    if failure_mode:
        expected=4 if failure_mode=='missing' else 5
        listen(True); wait_for(lambda: snapshot()['listen']['mic-a']['reason']==expected,'Listen helper failure reported')
        combined(True); wait_for(lambda: snapshot()['combined']['reason']==expected,'Combined helper failure reported')
        (work/'failure-state.json').write_text(json.dumps(snapshot(),indent=2)+'\n')
        assert not owned(),'failed helpers left nodes'
        for helper in ('pw-loopback','pw-cli'):
            p=tools/helper
            if p.exists(): p.unlink()
            p.symlink_to('/usr/bin/'+helper)
        listen(True); combined(True)
        wait_for(lambda: snapshot()['listen']['mic-a']['running'] and snapshot()['combined']['running'],'Retry after repair')
        listen(False); combined(False); wait_for(lambda: not owned(),'repaired routes remove')
        print('PASS: helper failure',failure_mode,'is explicit and retry succeeds',flush=True)
        raise SystemExit(0)
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
    for freq in (440,880):
        with wave.open(str(work/f'{freq}.wav'),'w') as f:
            f.setparams((2,2,rate,0,'NONE','not compressed'))
            f.writeframes(b''.join(struct.pack('<hh',*(int(3000*math.sin(2*math.pi*freq*i/rate)),)*2) for i in range(rate*4)))
    def capture(phase, devices):
        recorders=[record(device,name) for device,name in devices]
        time.sleep(.6)
        players=[spawn(['paplay','--device='+target,str(work/f'{freq}.wav')])
                 for target,freq in [('mic-bus',440),('out-a',880)]]
        time.sleep(.5)
        graph(phase+'-active-graph')
        (work/(phase+'-active-pulse.json')).write_text(json.dumps({kind:rows(kind) for kind in ('sources','sinks','source-outputs','sink-inputs')},indent=2))
        if not native:
            (work/(phase+'-pw-top.txt')).write_text(subprocess.check_output(['pw-top','-b','-n','2'],text=True))
        for p in players: assert p.wait(timeout=12)==0
        time.sleep(.2)
        for p in recorders: p.terminate(); p.wait(timeout=5)
        for f in files: f.flush()
        return {name:amplitudes(name) for _,name in devices}
    results=capture('listen',[('mic-a','ordinary-mic'),('out-a.monitor','listen-output'),('out-b.monitor','negative-output')])
    assert results['ordinary-mic']['440']>.06 and results['ordinary-mic']['880']<.001
    assert results['listen-output']['440']>.06 and results['listen-output']['880']>.06
    assert max(results['negative-output'].values())<.001
    listen(False)
    wait_for(lambda: not owned(),'Listen disable removes owned nodes')
    combined(True)
    wait_for(lambda: snapshot()['combined']['running'], 'Combined becomes active')
    assert {kind:pactl('get-default-'+kind).strip() for kind in defaults}==defaults,'Enabling routes must keep the existing defaults'
    results.update(capture('combined',[('plasma_pa_combined','combined')]))
    assert results['combined']['440']>.06 and results['combined']['880']>.06
    (work/'content.json').write_text(json.dumps(results,indent=2)+'\n')
    listen(False); combined(False)
    wait_for(lambda: not owned(),'disable removes all owned nodes')
    for _ in range(3):
        listen(True); wait_for(lambda: snapshot()['listen']['mic-a']['running'],'repeat enable')
        listen(False); wait_for(lambda: not owned(),'repeat disable')
    # Both stream-routing interfaces must keep the per-input choices truthful.
    create_mic('mic-b')
    listen(True); wait_for(lambda: snapshot()['listen']['mic-a']['running'],'before moving streams')
    route_id=snapshot()['listen']['mic-a']['id']
    for playback,target in ((True,'out-b'),(False,'mic-b'),(False,'mic-a'),(True,'out-a')):
        device=next(r for r in rows('sinks' if playback else 'sources') if r['name']==target)
        call('moveListen',GLib.Variant('(sbu)',(route_id,playback,device['index'])))
        field='output' if playback else 'source'
        time.sleep(.4)
        print('move',playback,target,snapshot(),flush=True)
        (work/('move-'+target+('-output' if playback else '-input')+'.json')).write_text(json.dumps({kind:rows(kind) for kind in ('sources','sinks','source-outputs','sink-inputs')},indent=2))
        wait_for(lambda: any(r['id']==route_id and r[field]==target and r['running'] for r in snapshot()['listen'].values()),'move reflected in settings')
    listen(False); wait_for(lambda: not owned(),'moved route removes cleanly')
    # Preferences survive an orderly service exit while its graph does not.
    listen(True); combined(True)
    wait_for(lambda: snapshot()['listen']['mic-a']['running'] and snapshot()['combined']['running'],'before service exit')
    service.terminate(); service.wait(timeout=8)
    wait_for(lambda: not owned(),'service exit removes owned graph')
    service=spawn(['kded6']); wait_for(service_ready,'restarted KDED')
    wait_for(lambda: snapshot()['listen']['mic-a']['running'] and snapshot()['combined']['running'],'saved choices restored')
    listen(False); combined(False); wait_for(lambda: not owned(),'restored graph removes')
    listen(True)
    wait_for(lambda: snapshot()['listen']['mic-a']['running'],'before missing input')
    pactl('unload-module',mic)
    wait_for(lambda: snapshot()['listen']['mic-a']['reason']==2,'missing input reported')
    wait_for(lambda: not owned(),'missing input removes route')
    create_mic('mic-a')
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
    assert {str(p.relative_to(work)):hashlib.sha256(p.read_bytes()).hexdigest() for p in person_files}==person_hashes
    (work/'person-files.json').write_text(json.dumps(person_hashes,indent=2)+'\n')
    if service_ready():
        (work/'final-state.json').write_text(json.dumps(snapshot(),indent=2)+'\n')
        (work/'final-defaults.json').write_text(json.dumps({kind:pactl('get-default-'+kind).strip() for kind in ('source','sink')},indent=2)+'\n')
    for p in reversed(children):
        if p.poll() is None: p.terminate()
    for p in children:
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
    for f in files+logs: f.close()
