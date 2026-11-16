#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Use the Sound window's actual controls, in a private container desktop."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import pyatspi
from PIL import ImageGrab

work=Path(sys.argv[1]); work.mkdir(parents=True,exist_ok=True)
scale=float(sys.argv[2])
os.environ.update(HOME=str(work/'home'),XDG_RUNTIME_DIR=str(work/'run'),XDG_CONFIG_HOME=str(work/'home/config'),
    DISPLAY=':19',QT_QPA_PLATFORM='xcb',QT_SCALE_FACTOR=str(scale),LC_ALL='C.UTF-8',
    QT_QUICK_BACKEND='software',LIBGL_ALWAYS_SOFTWARE='1',QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1',QT_ACCESSIBILITY='1',
    QT_PLUGIN_PATH='/opt/order19b/lib/x86_64-linux-gnu/plugins',QML_IMPORT_PATH='/opt/order19b/lib/x86_64-linux-gnu/qml',
    LD_LIBRARY_PATH='/opt/order19b/lib/x86_64-linux-gnu',XDG_DATA_DIRS='/opt/order19b/share:/usr/share')
for part in ('home/config','run'): (work/part).mkdir(mode=0o700,parents=True,exist_ok=True)
children=[]; logs=[]
def spawn(args):
    log=open(work/(Path(args[0]).name+str(len(children))+'.log'),'w'); logs.append(log)
    p=subprocess.Popen(args,stdout=log,stderr=log); children.append(p); return p
def run(args): return subprocess.check_output(args,text=True)
def pactl(*args): return run(['pactl',*args])
def wait(fn,label):
    for _ in range(150):
        try:
            value=fn()
            if value: return value
        except (subprocess.CalledProcessError,AssertionError): pass
        time.sleep(.1)
    raise AssertionError(label)
def nodes(obj):
    yield obj
    for c in obj: yield from nodes(c)
def find(name):
    for o in nodes(pyatspi.Registry.getDesktop(0)):
        if o.name!=name: continue
        try:
            rect=o.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
            if rect.width>0 and rect.height>0: return o
        except NotImplementedError: pass
    return None
def click(name):
    obj=wait(lambda: find(name),name)
    rect=obj.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
    assert rect.width>0 and rect.height>0,(name,list(rect))
    subprocess.run(['xdotool','mousemove',str(round((rect.x+rect.width/2)*scale)),str(round((rect.y+rect.height/2)*scale)),'click','1'],check=True)
    time.sleep(.5)
def keys(sequence): subprocess.run(['xdotool','key',*sequence],check=True); time.sleep(.7)
def capture(name):
    ImageGrab.grab().save(work/(name+'.png'))
    (work/(name+'.txt')).write_text('\n'.join(o.getRoleName()+' | '+o.name for o in nodes(pyatspi.Registry.getDesktop(0)))+'\n')
def snapshot():
    text=run(['gdbus','call','--session','--dest','org.kde.kded6','--object-path','/org/kde/plasma/AudioRoutes','--method','org.kde.plasma.AudioRoutes.snapshot'])
    import ast
    return json.loads(ast.literal_eval(text)[0])
try:
    subprocess.run(['dbus-update-activation-environment',*['%s=%s'%(k,v) for k,v in os.environ.items() if k.startswith(('QT_','QML_','XDG_','DISPLAY','HOME','LD_LIBRARY_PATH','LC_ALL'))]],check=True)
    spawn(['Xvfb',':19','-screen','0','1500x2300x24','-nolisten','tcp'])
    spawn(['pipewire']); wait(lambda: (work/'run/pipewire-0').exists(),'PipeWire')
    spawn(['wireplumber']); spawn(['pipewire-pulse']); wait(lambda: pactl('info'),'Pulse server')
    modules={name:pactl('load-module','module-null-sink','sink_name='+name).strip() for name in ('out-a','out-b','mic-bus')}
    mic=pactl('load-module','module-remap-source','master=mic-bus.monitor','source_name=mic-a').strip()
    spawn(['kded6'])
    run(['gdbus','call','--session','--dest','org.a11y.Bus','--object-path','/org/a11y/bus','--method','org.a11y.Bus.GetAddress'])
    spawn(['kcmshell6','kcm_pulseaudio'])
    wait(lambda: find('Listen to this device'),'Listen control')
    subprocess.run(['xdotool','search','--class','kcmshell6','windowsize','1450','2250','windowmove','0','0','windowfocus'],check=True)
    time.sleep(2); capture('off')
    assert not snapshot()['combined']['enabled'] and not snapshot()['listen']
    click('Listening output'); keys(['Home','Down','Return'])
    click('Listen to this device')
    wait(lambda: snapshot()['listen'].get('mic-a',{}).get('running'),'Listen active')
    assert snapshot()['listen']['mic-a']['output']=='out-b',snapshot()
    click('Combined recording input'); keys(['Home','Return'])
    click('Combined recording output'); keys(['Home','Return'])
    click('Combine output and microphone for recording')
    wait(lambda: snapshot()['combined']['running'],'Combined active')
    assert snapshot()['combined']['source']=='mic-a' and snapshot()['combined']['output']=='out-a'
    capture('active')
    pactl('unload-module',modules['out-b'])
    wait(lambda: snapshot()['listen']['mic-a']['reason']==3,'Missing output')
    time.sleep(1); capture('missing-output')
    assert 'is unavailable. This route will resume when it returns.' in (work/'missing-output.txt').read_text()
    pactl('unload-module',mic)
    wait(lambda: snapshot()['combined']['reason']==2,'Missing input')
    time.sleep(1); capture('missing-input')
    assert find('Stop Listening'),'Absent input retains a visible stop action'
    click('Stop Listening')
    click('Combine output and microphone for recording')
    assert not snapshot()['listen']['mic-a']['enabled'] and not snapshot()['combined']['enabled']
    (work/'snapshot.json').write_text(json.dumps(snapshot(),indent=2)+'\n')
    print('PASS: real page controls, explicit output, combined source, default off, missing output/input messages, disable; scale',scale)
finally:
    for p in reversed(children):
        if p.poll() is None: p.terminate()
    for p in children:
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
    for f in logs: f.close()
