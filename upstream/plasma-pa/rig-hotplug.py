#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
import json, subprocess, time, sys
from pathlib import Path
result=Path(sys.argv[1])
def pactl(*args):
    return subprocess.check_output(['pactl',*args],text=True).strip()
def default(name):
    for n in range(50):
        if pactl('get-default-sink') == name:
            return
        time.sleep(.1)
    raise AssertionError((name,pactl('get-default-sink')))
def bridge():
    sinks=json.loads(pactl('-f','json','list','sinks'))
    target=next(x['index'] for x in sinks if x['name']=='out-b')
    streams=json.loads(pactl('-f','json','list','sink-inputs'))
    row=next(x for x in streams if x['properties'].get('media.name')=='pa19-bridge-playback')
    assert row['sink']==target
pactl('set-default-sink','out-a')
default('out-a')
time.sleep(11)
for name,props in [('usb-headset','device.bus=usb'),('usb-speaker','device.bus=usb'),('bluez_output.rig','device.api=bluez5')]:
    module=pactl('load-module','module-null-sink','sink_name='+name,'sink_properties='+props)
    default(name)
    bridge()
    print('PASS: new output selected; bridge still on explicit out-b',name,flush=True)
    pactl('unload-module',module)
    default('out-a')
    bridge()
    print('PASS: chosen output restored',name,flush=True)
(result/'default-metadata.txt').write_text(subprocess.check_output(['pw-metadata','-n','default'],text=True))
print('PASS: headset, USB speaker and Bluetooth speaker policy; bridge routing retained',flush=True)
