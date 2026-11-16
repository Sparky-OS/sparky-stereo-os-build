#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the combine-stream content oracle in a private container session."""
import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time
import wave

work = Path('/work19/mix-prototype')
work.mkdir(exist_ok=True)
os.environ.update(XDG_RUNTIME_DIR=str(work/'run'), HOME=str(work/'home'))
Path(os.environ['XDG_RUNTIME_DIR']).mkdir(mode=0o700, exist_ok=True)
Path(os.environ['HOME']).mkdir(exist_ok=True)
children = []
logs = []

def spawn(args):
    log = open(work/(Path(args[0]).name+str(len(children))+'.log'), 'w')
    logs.append(log)
    p = subprocess.Popen(args, stdout=log, stderr=log)
    children.append(p)
    return p

def pactl(*args):
    return subprocess.check_output(['pactl', *args], text=True)

def wait_for(fn):
    for _ in range(100):
        try:
            if fn(): return
        except (subprocess.CalledProcessError, FileNotFoundError): pass
        time.sleep(.1)
    raise RuntimeError('fixture did not become ready')

try:
    spawn(['pipewire'])
    wait_for(lambda: (work/'run/pipewire-0').exists())
    spawn(['wireplumber'])
    spawn(['pipewire-pulse'])
    wait_for(lambda: bool(pactl('info')))
    for sink in ('out-a', 'mic-a'):
        pactl('load-module', 'module-null-sink', 'sink_name='+sink)
    args = {
        'combine.mode': 'source', 'node.name': 'pa19-combined',
        'node.description': 'Combined Recording',
        'combine.props': {'audio.position': ['FL','FR'], 'node.virtual': False},
        'stream.props': {'node.virtual': False, 'node.dont-fallback': True,
                         'node.passive': True},
        'stream.rules': [
            {'matches': [{'node.name': name}], 'actions': {'create-stream': {
                'stream.capture.sink': True, 'audio.position': ['FL','FR'],
                'combine.audio.position': ['FL','FR']}}}
            for name in ('out-a','mic-a')]
    }
    spawn(['pw-cli', '-m', 'load-module', 'libpipewire-module-combine-stream', json.dumps(args)])
    wait_for(lambda: 'pa19-combined' in pactl('list', 'short', 'sources'))
    for freq in (440, 880):
        with wave.open(str(work/f'{freq}.wav'), 'w') as f:
            f.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
            f.writeframes(b''.join(struct.pack('<hh', *(int(3000*math.sin(2*math.pi*freq*i/48000)),)*2) for i in range(48000*4)))
    output = open(work/'mixed.f32', 'wb')
    recorder = subprocess.Popen(['parec','--raw','--format=float32le','--rate=48000','--channels=2','--device=pa19-combined'], stdout=output)
    children.append(recorder)
    time.sleep(.5)
    players = [spawn(['paplay', '--device='+target, str(work/f'{freq}.wav')]) for target,freq in (('mic-a',440),('out-a',880))]
    for p in players: assert p.wait(timeout=12) == 0
    time.sleep(.3)
    recorder.terminate(); recorder.wait(); output.close()
    data = (work/'mixed.f32').read_bytes()
    samples = struct.unpack('<'+'f'*(len(data)//4), data)[::2]
    # Find a one-second window with content, then independently detect both tones.
    start = next(i for i,x in enumerate(samples) if abs(x)>.03)+2400
    window = samples[start:start+48000]
    assert len(window) == 48000
    def amplitude(freq):
        return 2*abs(sum(x*complex(math.cos(2*math.pi*freq*i/48000), -math.sin(2*math.pi*freq*i/48000)) for i,x in enumerate(window)))/len(window)
    result = {str(f): amplitude(f) for f in (440,880,1333)}
    assert result['440']>.06 and result['880']>.06 and result['1333']<.001, result
    result['peak'] = max(map(abs, samples))
    result['result'] = 'PASS: both independent contributors mixed into one stereo source'
    (work/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    (work/'nodes.json').write_text(subprocess.check_output(['pw-dump'], text=True))
    print(json.dumps(result,indent=2))
finally:
    for p in reversed(children):
        if p.poll() is None: p.terminate()
    for p in children:
        try: p.wait(timeout=5)
        except subprocess.TimeoutExpired: p.kill(); p.wait()
    for log in logs: log.close()
