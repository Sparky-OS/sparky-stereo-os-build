#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import subprocess, time, sys, os, re, json
from pathlib import Path
import pyatspi
from PIL import ImageGrab
result=Path(sys.argv[1])
mode=sys.argv[2]

def walk(obj,depth=0):
    yield obj,depth
    for c in obj:
        yield from walk(c,depth+1)

def find(name, role=None):
    for obj,depth in walk(pyatspi.Registry.getDesktop(0)):
        if obj.name == name and (role is None or role==obj.getRoleName()):
            return obj
    raise AssertionError((name,role))

def click(obj):
    r=obj.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
    scale=float(os.environ.get('QT_SCALE_FACTOR','1'))
    assert r.width>0 and r.height>0,(obj.name,list(r))
    print('click',obj.name,list(r),flush=True)
    subprocess.run(['xdotool','mousemove',str(round((r.x+r.width/2)*scale)),str(round((r.y+r.height/2)*scale)),'click','1'],check=True)
    time.sleep(1)

def snapshot(name):
    rows=[f'{"  "*depth}{obj.getRoleName()} | {obj.name}' for obj,depth in walk(pyatspi.Registry.getDesktop(0))]
    (result/(name+'.txt')).write_text('\n'.join(rows)+'\n')
    ImageGrab.grab().save(result/(name+'.png'))
    print(name,[r.strip() for r in rows if 'pa19-' in r or 'virtual' in r],flush=True)
    return '\n'.join(rows)

def menu_click(process, fraction, filename):
    windows=subprocess.check_output(['xdotool','search','--onlyvisible','--pid',str(process.pid)],text=True).split()
    menus=[]
    for wid in windows:
        info=subprocess.check_output(['xwininfo','-id',wid],text=True)
        if 'Override Redirect State: yes' in info:
            menus.append(info)
    assert len(menus)==1,menus
    (result/filename).write_text(menus[0])
    def value(key):
        return int(re.search(re.escape(key)+r':\s+(-?\d+)',menus[0]).group(1))
    x=value('Absolute upper-left X')+value('Width')//2
    y=value('Absolute upper-left Y')+round(value('Height')*fraction)
    subprocess.run(['xdotool','mousemove',str(x),str(y),'click','1'],check=True)

p=subprocess.Popen(['plasmawindowed','org.kde.plasma.volume'],stdout=(result/'applet.log').open('w'),stderr=subprocess.STDOUT)
try:
    time.sleep(6)
    subprocess.run(['xdotool','search','--class','plasmawindowed','windowsize','1000','900','windowmove','0','0','windowfocus'],check=False)
    time.sleep(2)
    click(find('Applications','page tab'))
    off=snapshot('applet-off')
    assert 'pa19-module-' not in off and 'pa19-filter-playback' not in off
    click(find('More actions','check box'))
    snapshot('applet-menu')
    name='Show virtual devices and streams' if mode=='candidate' else 'Show virtual devices'
    menu_click(p, 5/6, 'menu-geometry.txt')
    time.sleep(2)
    on=snapshot('applet-on')
    if mode=='candidate':
        for n in ['pa19-module-playback','pa19-module-capture','pa19-filter-playback']:
            assert n in on,n
    else:
        assert 'pa19-module-' not in on and 'pa19-filter-playback' not in on
    if os.environ.get('PA19_APPLET_OWNED')=='1':
        import ast
        def state():
            value=subprocess.check_output(['gdbus','call','--session','--dest','org.kde.kded6','--object-path','/org/kde/plasma/AudioRoutes','--method','org.kde.plasma.AudioRoutes.snapshot'],text=True)
            return json.loads(ast.literal_eval(value)[0])
        before=state()
        assert before['listen']['mic-a']['output']=='out-a'
        item=next(obj for obj,depth in walk(pyatspi.Registry.getDesktop(0)) if obj.getRoleName()=='list item' and 'Listen:' in obj.name and not any('Listen:' in c.name for c in obj if c.getRoleName()=='list item'))
        if os.environ.get('PA19_CHECK_NAMES')=='1':
            expected='Listen: '+before['listen']['mic-a']['sourceLabel']
            assert item.name==expected,(item.name,expected)
            combined=[obj.name for obj,depth in walk(pyatspi.Registry.getDesktop(0)) if obj.getRoleName()=='list item' and 'Combined Recording' in obj.name]
            assert len(combined)==2 and all(n.startswith('Combined Recording: ') for n in combined),combined
            assert all('pw-cli' not in n for n in combined),combined
        button=next(c for c in item if c.name=='Additional Options' and c.getRoleName()=='push button menu')
        click(button)
        snapshot('owned-route-menu')
        menu_click(p,5/8,'owned-menu-geometry.txt')
        for _ in range(100):
            after=state()
            if after['listen']['mic-a']['output']=='out-b' and after['listen']['mic-a']['running']: break
            time.sleep(.1)
        else: raise AssertionError(after)
        sinks=json.loads(subprocess.check_output(['pactl','-f','json','list','sinks']))
        target=next(x['index'] for x in sinks if x['name']=='out-b')
        rows=json.loads(subprocess.check_output(['pactl','-f','json','list','sink-inputs']))
        stream=next(x for x in rows if x['properties'].get('plasma.pa.route')=='Listen-hotplug-check')
        assert stream['sink']==target,(stream,target)
        (result/'owned-route-state.json').write_text(json.dumps({'before':before,'after':after,'sink_inputs':rows},indent=2)+'\n')
        snapshot('owned-routed')
        print('PASS: actual widget menu updates owned route preferences and server target',flush=True)
    elif mode=='candidate':
        for name, fraction, kind, field, target in [
            ('pa19-module-playback',5/8,'sink-inputs','sink','out-b'),
            ('pa19-filter-playback',5/8,'sink-inputs','sink','out-b'),
            ('pa19-module-capture · pa19-module-capture',5/6,'source-outputs','source','mic-b'),
        ]:
            item=find(name,'list item')
            button=next(c for c in item if c.name=='Additional Options' and c.getRoleName()=='push button menu')
            click(button)
            snapshot('route-menu-'+kind+'-'+name.split(' · ')[0])
            menu_click(p,fraction,'route-'+name.split(' · ')[0]+'-geometry.txt')
            time.sleep(1)
            devices=json.loads(subprocess.check_output(['pactl','-f','json','list','sinks' if field=='sink' else 'sources']))
            wanted=next(x['index'] for x in devices if x['name']==target)
            rows=json.loads(subprocess.check_output(['pactl','-f','json','list',kind]))
            stream=next(x for x in rows if x['properties'].get('media.name')==name.split(' · ')[0])
            assert stream[field]==wanted,(name,stream[field],wanted)
            (result/('routed-'+kind+'.json')).write_text(json.dumps(rows,indent=2))
        snapshot('applet-routed')
    print('PASS: applet '+mode,flush=True)
finally:
    p.terminate()
    p.wait(timeout=10)
