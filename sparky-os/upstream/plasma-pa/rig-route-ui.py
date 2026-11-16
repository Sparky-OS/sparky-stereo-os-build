#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Use the Sound window's actual controls, in a private container desktop."""
import json
import gettext
import os
from pathlib import Path
import subprocess
import sys
import time
import pyatspi
from PIL import ImageGrab

work=Path(sys.argv[1]); work.mkdir(parents=True,exist_ok=True)
scale=float(sys.argv[2])
prefix='/usr' if os.environ.get('PA19_INSTALLED')=='1' else '/opt/order19b'
os.environ.update(HOME=str(work/'home'),XDG_RUNTIME_DIR=str(work/'run'),XDG_CONFIG_HOME=str(work/'home/config'),
    DISPLAY=':19',QT_QPA_PLATFORM='xcb',QT_SCALE_FACTOR=str(scale),LC_ALL=os.environ.get('PA19_LOCALE','C.UTF-8'),
    QT_QUICK_BACKEND='software',LIBGL_ALWAYS_SOFTWARE='1',QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1',QT_ACCESSIBILITY='1',
    QT_PLUGIN_PATH=prefix+'/lib/x86_64-linux-gnu/plugins',QML_IMPORT_PATH=prefix+'/lib/x86_64-linux-gnu/qml',
    LD_LIBRARY_PATH=prefix+'/lib/x86_64-linux-gnu',XDG_DATA_DIRS=prefix+'/share:/usr/share')
language=os.environ.get('PA19_LANGUAGE','en')
os.environ['LANGUAGE']=language
if os.environ.get('PA19_INSTALLED')=='1':
    for key in ('QT_PLUGIN_PATH','QML_IMPORT_PATH','LD_LIBRARY_PATH'): os.environ.pop(key,None)
catalogue=gettext.translation('kcm_pulseaudio',localedir=prefix+'/share/locale',languages=[language],fallback=language=='en')
T=catalogue.gettext
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
    subprocess.run(['dbus-update-activation-environment',*['%s=%s'%(k,v) for k,v in os.environ.items() if k.startswith(('QT_','QML_','XDG_','DISPLAY','HOME','LD_LIBRARY_PATH','LC_ALL','LANGUAGE'))]],check=True)
    spawn(['Xvfb',':19','-screen','0','1500x2300x24','-nolisten','tcp'])
    spawn(['pipewire']); wait(lambda: (work/'run/pipewire-0').exists(),'PipeWire')
    spawn(['wireplumber']); spawn(['pipewire-pulse']); wait(lambda: pactl('info'),'Pulse server')
    modules={name:pactl('load-module','module-null-sink','sink_name='+name,'sink_properties=device.description='+name).strip() for name in ('out-a','out-b','mic-bus')}
    mic=pactl('load-module','module-remap-source','master=mic-bus.monitor','source_name=mic-a').strip()
    service_env=dict(os.environ)
    if os.environ.get('PA19_UI_FAILURE')=='missing':
        tools=work/'tools'; tools.mkdir(); service_env['PATH']=str(tools)
    log=open(work/'kded.log','w'); logs.append(log)
    service=subprocess.Popen(['/usr/bin/kded6'],env=service_env,stdout=log,stderr=log); children.append(service)
    run(['gdbus','call','--session','--dest','org.a11y.Bus','--object-path','/org/a11y/bus','--method','org.a11y.Bus.GetAddress'])
    window=spawn(['kcmshell6','kcm_pulseaudio'])
    wait(lambda: find(T('Listen to this device')),'Listen control')
    subprocess.run(['xdotool','search','--class','kcmshell6','windowsize','1450','2250','windowmove','0','0','windowfocus'],check=True)
    time.sleep(2); capture('off')
    assert not snapshot()['combined']['enabled'] and not snapshot()['listen']
    click(T('Listening output')); keys(['Home','Down','Return'])
    click(T('Listen to this device'))
    if os.environ.get('PA19_UI_FAILURE')=='missing':
        wait(lambda: snapshot()['listen']['mic-a']['reason']==4,'missing helper')
        time.sleep(1); capture('helper-unavailable')
        message=T('Could not start %1. Install the audio backend tools and try again.').replace('%1','pw-loopback')
        assert message in (work/'helper-unavailable.txt').read_text(),message
        click(T('Listen to this device'))
        print('PASS: localized missing-helper failure in the real page',language)
        raise SystemExit(0)
    wait(lambda: snapshot()['listen'].get('mic-a',{}).get('running'),'Listen active')
    assert snapshot()['listen']['mic-a']['output']=='out-b',snapshot()
    click(T('Combined recording input')); keys(['Home','Return'])
    click(T('Combined recording output')); keys(['Home','Return'])
    click(T('Combine output and microphone for recording'))
    wait(lambda: snapshot()['combined']['running'],'Combined active')
    assert snapshot()['combined']['source']=='mic-a' and snapshot()['combined']['output']=='out-a'
    capture('active')
    assert find(T('Choose the microphone and output in Combined Recording.'))
    if os.environ.get('PA19_CHECK_NAMES')=='1':
        text=(work/'active.txt').read_text()
        assert 'pw-loopback:' not in text and 'pw-cli:' not in text, 'Helper names are visible in stream labels'
        expected=T('Listen: %1').replace('%1',snapshot()['listen']['mic-a']['sourceLabel'])
        assert expected in text,expected
    # Move the owned playback stream using the page's ordinary stream selector.
    def owned_playback_combo():
        for obj in nodes(pyatspi.Registry.getDesktop(0)):
            if obj.getRoleName()!='label' or T('Listen: %1').split('%1')[0].strip() not in obj.name: continue
            for sibling in obj.parent:
                if sibling.getRoleName()=='combo box' and sibling.name.startswith('out-'):
                    return sibling
        return None
    for index,target in ((0,'out-a'),(1,'out-b')):
        obj=wait(owned_playback_combo,'owned stream selector')
        rect=obj.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
        subprocess.run(['xdotool','mousemove',str(round((rect.x+rect.width/2)*scale)),str(round((rect.y+rect.height/2)*scale)),'click','1'],check=True)
        keys(['Home']+(['Down'] if index else [])+['Return'])
        wait(lambda: snapshot()['listen']['mic-a']['output']==target and snapshot()['listen']['mic-a']['running'],'stream selector changes saved target')
        warning=T('This microphone is also being sent to this output. The combined recording captures it twice, which can cause an echo.')
        if target=='out-a':
            wait(lambda: find(warning),'same microphone/output warning')
            capture('same-output-warning')
        else:
            wait(lambda: not find(warning),'warning clears for separate output')
    capture('stream-routed')
    window.terminate(); window.wait(timeout=5)
    time.sleep(1)
    assert snapshot()['listen']['mic-a']['running'] and snapshot()['combined']['running'],'Closing the page stopped the routes'
    window=spawn(['kcmshell6','kcm_pulseaudio'])
    wait(lambda: find(T('Listen to this device')),'reopened page')
    subprocess.run(['xdotool','search','--class','kcmshell6','windowsize','1450','2250','windowmove','0','0','windowfocus'],check=True)
    time.sleep(1); capture('reopened')
    pactl('unload-module',modules['out-b'])
    wait(lambda: snapshot()['listen']['mic-a']['reason']==3,'Missing output')
    time.sleep(1); capture('missing-output')
    assert T('The output %1 is unavailable. This route will resume when it returns.').split('%1')[0] in (work/'missing-output.txt').read_text()
    pactl('unload-module',mic)
    wait(lambda: snapshot()['combined']['reason']==2,'Missing input')
    time.sleep(1); capture('missing-input')
    assert find(T('Stop Listening')),'Absent input retains a visible stop action'
    click(T('Stop Listening'))
    click(T('Combine output and microphone for recording'))
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
