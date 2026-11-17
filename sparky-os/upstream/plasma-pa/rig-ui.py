#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import sys, time, subprocess, json, os
from pathlib import Path
import pyatspi
from PIL import ImageGrab
result = Path(sys.argv[1])
mode = sys.argv[2]

def tree(obj, depth=0):
    rows = []
    try:
        rows.append('  '*depth + f'{obj.getRoleName()} | {obj.name}')
        for child in obj:
            rows.extend(tree(child, depth+1))
    except Exception:
        pass
    return rows

def snapshot(name):
    rows = tree(pyatspi.Registry.getDesktop(0))
    (result/(name+'.txt')).write_text('\n'.join(rows)+'\n')
    ImageGrab.grab().save(result/(name+'.png'))
    print(name, [r.strip() for r in rows if 'label |' in r and 'pa19-' in r])

def nodes(obj):
    yield obj
    for child in obj:
        yield from nodes(child)

def find(name, role=None):
    for obj in nodes(pyatspi.Registry.getDesktop(0)):
        if obj.name == name and (role is None or obj.getRoleName() == role):
            return obj
    raise AssertionError(f'Accessible object missing: {name} {role}')

def press(obj):
    rect = obj.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
    print('click',obj.name,list(rect))
    assert rect.width > 0 and rect.height > 0
    scale = float(os.environ.get('QT_SCALE_FACTOR','1'))
    subprocess.run(['xdotool','mousemove',str(round((rect.x+rect.width/2)*scale)),str(round((rect.y+rect.height/2)*scale)),'click','1'],check=True)
    time.sleep(1)

def route(label, target):
    obj = find(label, 'label')
    combos = [c for c in obj.parent if c.getRoleName() == 'combo box']
    assert len(combos) == 1, label
    press(combos[0])
    # Both fixture target models list a then b; select b through real keys.
    subprocess.run(['xdotool', 'key', 'Home', 'Down', 'Return'], check=True)
    time.sleep(1)
    assert combos[0].name == target, (label, combos[0].name, target)

def pulse_check():
    sinks = json.loads(subprocess.check_output(['pactl','-f','json','list','sinks']))
    sources = json.loads(subprocess.check_output(['pactl','-f','json','list','sources']))
    sink_b = next(x['index'] for x in sinks if x['name']=='out-b')
    source_b = next(x['index'] for x in sources if x['name']=='mic-b')
    for kind, field, expected, names in [
        ('sink-inputs','sink',sink_b,['pa19-module-playback','pa19-filter-playback']),
        ('source-outputs','source',source_b,['pa19-module-capture']),
    ]:
        data = json.loads(subprocess.check_output(['pactl','-f','json','list',kind]))
        (result/('routed-'+kind+'.json')).write_text(json.dumps(data,indent=2))
        for name in names:
            row = next(x for x in data if x['properties'].get('media.name')==name)
            assert row[field] == expected, (name,row[field],expected)

subprocess.run(['xdotool','search','--class','kcmshell6','windowsize','1560',os.environ.get('PA19_WINDOW_HEIGHT','1700'),'windowmove','0','0','windowfocus'], check=False)
time.sleep(2)
snapshot('off')
off = (result/'off.txt').read_text()
assert 'label | pa19-module-playback' not in off
assert 'label | pa19-module-capture' not in off
assert 'label | pa19-filter-playback' not in off
assert 'label | pw-loopback: pa19-bridge-playback' in off
assert 'label | pw-loopback: pa19-bridge-capture' in off
if mode == 'published' and os.environ.get('EXPECT_VISIBLE') == '1':
    find('pa19-module-playback', 'label')
if mode == 'candidate':
    press(find('Show Virtual Streams'))
    snapshot('on')
    saved = Path(os.environ['XDG_CONFIG_HOME'])/'plasmaparc'
    (result/'plasmaparc-on.txt').write_text(saved.read_text())
    assert subprocess.check_output(['kreadconfig6','--file','plasmaparc','--group','General','--key','ShowVirtualStreams','--default','false'],text=True).strip() == 'true'
    for name in ['pa19-module-playback','pa19-module-capture','pa19-filter-playback']:
        find(name, 'label')
    route('pa19-module-playback','out-b')
    route('pa19-filter-playback','out-b')
    route('pa19-module-capture','mic-b')
    pulse_check()
    snapshot('routed')
    press(find('Show Virtual Streams'))
    snapshot('off-again')
    assert 'label | pa19-module-playback' not in (result/'off-again.txt').read_text()
    assert subprocess.check_output(['kreadconfig6','--file','plasmaparc','--group','General','--key','ShowVirtualStreams','--default','false'],text=True).strip() == 'false'
print('PASS: virtual streams hidden in the control; bridge retained; ' + ('all three virtual routes changed through the page' if mode=='candidate' else 'published red reproduced'))
