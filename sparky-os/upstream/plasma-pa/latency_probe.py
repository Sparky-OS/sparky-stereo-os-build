#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Measure the software path with one shared four-channel capture."""
import json
import math
import random
import struct
import subprocess
import time
import wave


def run(work, spawn, pactl, wait_for, rate):
    args={
        'combine.mode':'source','node.name':'pa19-latency-probe',
        'combine.latency-compensate':False,
        'combine.props':{'audio.position':['FL','FR','RL','RR'],'priority.session':0},
        'stream.props':{'node.passive':True,'resample.disable':True,'node.dont-fallback':True},
        'stream.rules':[
            {'matches':[{'node.name':name}],'actions':{'create-stream':{
                'stream.capture.sink':monitor,'audio.position':['FL','FR'],
                'combine.audio.position':positions}}}
            for name,monitor,positions in [('mic-a',False,['FL','FR']),('out-a',True,['RL','RR'])]]}
    helper=spawn(['pw-cli','-m','load-module','libpipewire-module-combine-stream',json.dumps(args)])
    wait_for(lambda: 'pa19-latency-probe' in pactl('list','short','sources'),'latency probe source')
    random_source=random.Random(19)
    noise=[2000 if random_source.getrandbits(1) else -2000 for _ in range(rate//4)]
    signal=[0]*(rate//2)+noise+[0]*(rate*2)
    with wave.open(str(work/'marker.wav'),'w') as f:
        f.setparams((2,2,rate,0,'NONE','not compressed'))
        f.writeframes(b''.join(struct.pack('<hh',x,x) for x in signal))
    with (work/'latency.f32').open('wb') as output:
        recorder=spawn(['parec','--raw','--format=float32le','--rate='+str(rate),'--channels=4',
                        '--channel-map=front-left,front-right,rear-left,rear-right',
                        '--device=pa19-latency-probe'],output)
        time.sleep(.6)
        player=spawn(['paplay','--device=mic-bus',str(work/'marker.wav')])
        assert player.wait(timeout=12)==0
        time.sleep(.3); recorder.terminate(); recorder.wait(timeout=5)
    helper.terminate(); helper.wait(timeout=5)
    raw=(work/'latency.f32').read_bytes()
    samples=struct.unpack('<'+'f'*(len(raw)//4),raw)
    reference,monitored=samples[0::4],samples[2::4]
    first_reference=next(i for i,x in enumerate(reference) if abs(x)>.01)
    first_monitored=next(i for i,x in enumerate(monitored) if abs(x)>.01)
    delay=first_monitored-first_reference
    assert 0<=delay<rate//2,delay
    length=rate//8
    a=reference[first_reference:first_reference+length]
    b=monitored[first_monitored:first_monitored+length]
    correlation=sum(x*y for x,y in zip(a,b))/math.sqrt(sum(x*x for x in a)*sum(x*x for x in b))
    assert correlation>.999,correlation
    result={'rate':rate,'delaySamples':delay,'delayMs':1000*delay/rate,'correlation':correlation,
            'method':'microphone FL and selected output monitor RL in one four-channel capture; probe compensation disabled',
            'scope':'software null-device graph including the two probe branches; physical latency is not measured'}
    (work/'latency.json').write_text(json.dumps(result,indent=2)+'\n')
    (work/'latency-graph.json').write_text(subprocess.check_output(['pw-dump'],text=True))
    print(json.dumps(result,indent=2),flush=True)
