#!/usr/bin/python3 -I
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Fake HDMI/ALSA transport, the real Pulse negotiation and a decoder fallback.
Run under dbus-run-session in a container without sound devices or a network.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import numpy as np

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('surround',HERE.parents[1]/'lib/surround.py')
s=importlib.util.module_from_spec(spec);spec.loader.exec_module(s)

def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)

def wait(predicate):
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        result=predicate()
        if result:return result
        time.sleep(.1)
    raise AssertionError('private graph timeout')

def nodes():
    p=subprocess.run(['pw-dump'],capture_output=True,text=True)
    return json.loads(p.stdout) if p.returncode==0 else []

def eld(codes):
    text='monitor_present 1\neld_valid 1\nsad_count %d\n'%(len(codes)+1)
    text+='sad0_coding_type [0x1] LPCM\nsad0_channels 2\nsad0_rates [0x40] 48000\nsad0_bits [0xe] 16 20 24\n'
    for i,code in enumerate(codes,1):text+='sad%d_coding_type [0x%x]\n'%(i,code)
    return text

def main():
  with tempfile.TemporaryDirectory(prefix='as21-spdif-',dir='/work') as folder:
    root=Path(folder); runtime=root/'runtime';runtime.mkdir(mode=0o700)
    os.environ.update(XDG_RUNTIME_DIR=str(runtime),HOME=str(root),XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'))
    plugin=root/'libasound_module_pcm_as21.so';client=root/'client'
    run('gcc','-shared','-fPIC','-DPIC','-O2',str(HERE/'pcm_fixture.c'),'-lasound','-o',str(plugin))
    run('gcc','-O2',str(HERE/'client.c'),'-lpulse','-o',str(client))
    # Private override of ALSA's hdmi name. AES arguments are accepted so that
    # PipeWire's real IEC 61937 open path runs unchanged; no /dev/snd is present.
    asound=root/'asound.conf'
    asound.write_text('''</usr/share/alsa/alsa.conf>
pcm_type.as21 { lib "%s" }
pcm.!hdmi {
 @args [ CARD DEV AES0 AES1 AES2 AES3 ]
 @args.CARD { type string default "encoded" }
 @args.DEV { type integer default 0 }
 @args.AES0 { type integer default 0 }
 @args.AES1 { type integer default 0 }
 @args.AES2 { type integer default 0 }
 @args.AES3 { type integer default 0 }
 type as21
 rates "48000"
 formats "S16_LE S32_LE"
 channels 2
 out { @func concat strings [ "%s/" $CARD ".raw" ] }
}
'''%(plugin,root))
    os.environ['ALSA_CONFIG_PATH']=str(asound)
    conf=root/'config/pipewire/pipewire.conf.d';conf.mkdir(parents=True)
    objects=[]
    descriptors={}
    fixtures=json.loads((HERE/'cta-fixtures.json').read_text())
    for name,fixture in fixtures.items():
      block=bytes.fromhex(fixture['audio_data_block_hex'])
      assert block[0] >> 5 == 1 and block[0] & 31 == len(block)-1
      sads=[block[i:i+3] for i in range(1,len(block),3)]
      codes=[sad[0] >> 3 & 15 for sad in sads if sad[0] >> 3 & 15 != 1]
      assert codes == fixture['encoded_codes']
      # The fixture supplies the ELD view that ALSA's connector monitor exports.
      # The independent block bytes are retained so capability provenance is explicit.
      text=eld(codes);descriptors[name]={'cta_audio_data_block_hex':block.hex(),'eld':text}
      (root/(name+'.eld')).write_text(text)
      objects.append({'factory':'adapter','args':{
       'factory.name':'api.alsa.pcm.sink','node.name':'as21-'+name,'media.class':'Audio/Sink',
       'api.alsa.path':'hdmi:CARD='+name+',DEV=0','api.alsa.disable-mmap':True,
       'audio.position':['FL','FR'],'iec958.codecs':['PCM']+s.eld_formats(text),
       'iec958.codecs.detected':json.dumps(s.eld_formats(text)),
       'session.suspend-timeout-seconds':0}})
    (conf/'fake-hdmi.conf').write_text(json.dumps({'context.objects':objects},indent=2))
    if os.environ.get('AS21_BASELINE') != '1' and os.environ.get('AS21_INSTALLED') != '1':
      wpconf=root/'config/wireplumber/wireplumber.conf.d';wpconf.mkdir(parents=True)
      source_dir=HERE.parents[1]/'wireplumber'
      text=(source_dir/'00-sparky-stereo-surround.conf').read_text()
      text=text.replace('name = sparky-stereo-audio.lua','name = "'+str(source_dir/'sparky-stereo-audio.lua')+'"')
      (wpconf/'00-surround.conf').write_text(text)
    ac3=root/'source.ac3';spdif=root/'source.spdif';decoded=root/'decoded.raw'
    run('ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i','sine=frequency=997:sample_rate=48000:duration=1',
        '-ac','2','-c:a','ac3','-b:a','192k',str(ac3))
    run('ffmpeg','-hide_banner','-loglevel','error','-i',str(ac3),'-c:a','copy','-f','spdif',str(spdif))
    processes=[];logs=[]
    def start(command,name):
      log=open('/evidence/passthrough-'+name+'.log','w');logs.append(log)
      p=subprocess.Popen(command,stdout=log,stderr=log);processes.append(p);return p
    try:
      start(['pipewire'],'pipewire')
      wait(lambda:(runtime/'pipewire-0').exists())
      start(['wireplumber'],'wireplumber')
      start(['pipewire-pulse'],'pulse')
      wait(lambda:(runtime/'pulse/native').exists())
      wait(lambda:len([o for o in nodes() if o.get('info',{}).get('props',{}).get('node.name','').startswith('as21-')])==2)
      Path('/evidence/passthrough-initial-graph.json').write_text(json.dumps(nodes(),indent=2))
      Path('/evidence/passthrough-pulse-sinks.json').write_text(subprocess.check_output(['pactl','--format=json','list','sinks'],text=True))
      engine='/usr/bin/sparky-stereo-audio' if os.environ.get('AS21_INSTALLED') == '1' else str(HERE.parents[1]/'bin/sparky-stereo-audio')
      start([engine,'monitor'],'monitor')
      if os.environ.get('AS21_REJECT') == '1': start(['pw-dump','-m'],'failure-events')
      if os.environ.get('AS21_REJECT') == '1':
        proc=start([str(client),'as21-encoded',str(spdif),str(decoded),'ac3'],'refused-client')
        def problem():
          data=json.loads(subprocess.check_output(['sparky-stereo-problems','list','--json','sparky-stereo-audio'],text=True))
          return data if 'passthrough:as21-encoded' in json.dumps(data) else None
        try:
          kept=wait(problem)
        except AssertionError:
          Path('/evidence/passthrough-refusal-graph.json').write_text(json.dumps(nodes(),indent=2))
          raise
        Path('/evidence/passthrough-refusal-problem.json').write_text(json.dumps(kept,indent=2)+'\n')
        print(json.dumps(kept,indent=2));return
      if os.environ.get('AS21_INSTALLED') == '1':
        run(engine,'passthrough','--output','as21-encoded','--codec','DTS=off')
        formats=lambda: next(x['formats'] for x in json.loads(subprocess.check_output(['pactl','--format=json','list','sinks'],text=True)) if x['name']=='as21-encoded')
        assert 'dts-iec61937' not in json.dumps(formats())
        assert 'ac3-iec61937' in json.dumps(formats())
        run(engine,'passthrough','--output','as21-encoded','--codec','DTS=auto')
        assert 'dts-iec61937' in json.dumps(formats())
        run(engine,'passthrough','--output','as21-pcm','--codec','AC3=auto')
        pcm=next(x for x in json.loads(subprocess.check_output(['pactl','--format=json','list','sinks'],text=True)) if x['name']=='as21-pcm')
        assert 'ac3-iec61937' not in json.dumps(pcm['formats'])
      results=[]
      for name in ('encoded','pcm'):
        proc=subprocess.Popen([str(client),'as21-'+name,str(spdif),str(decoded),'ac3'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        processes.append(proc)
        time.sleep(.2)
        Path('/evidence/passthrough-client-'+name+'-graph.json').write_text(json.dumps(nodes(),indent=2))
        stdout,stderr=proc.communicate(timeout=20)
        p=subprocess.CompletedProcess(proc.args,proc.returncode,stdout,stderr)
        if name=='pcm':
          assert p.returncode!=0,('encoded request unexpectedly succeeded',p.stdout,p.stderr)
          run('ffmpeg','-hide_banner','-loglevel','error','-i',str(ac3),'-f','s16le','-ac','2',str(decoded))
          p=subprocess.run([str(client),'as21-'+name,str(spdif),str(decoded),'pcm'],capture_output=True,text=True,timeout=20)
        assert p.returncode==0,(p.returncode,p.stdout,p.stderr)
        if name=='encoded':
          assert 'requested=ac3-iec61937' in p.stdout,p.stdout
          raw=(root/'encoded.raw.S16_LE').read_bytes()
          payload=spdif.read_bytes();offset=raw.find(payload)
          assert offset>=0,(len(raw),len(payload))
          result={'sink':name,'negotiation':p.stdout.strip(),'payload_bytes':len(payload),
                  'received_bytes':len(raw),'payload_offset':offset,'bit_exact':True}
        else:
          assert 'requested=pcm' in p.stdout,p.stdout
          raw=(root/'pcm.raw.S32_LE').read_bytes()
          golden=(np.fromfile(decoded,dtype='<i2').astype('<i4')*65536).tobytes()
          offset=raw.find(golden)
          assert offset>=0,(len(raw),len(golden))
          assert spdif.read_bytes() not in raw
          result={'sink':name,'negotiation':p.stdout.strip(),'decoded_bytes':len(golden),
                  'received_bytes':len(raw),'pcm_offset':offset,'decoded_exact':True}
        results.append(result)
      Path('/evidence/passthrough-results.json').write_text(json.dumps({'eld':descriptors,'results':results},indent=2)+'\n')
      print(json.dumps(results,indent=2))
    finally:
      for p in reversed(processes):
        if p.poll() is None:
          p.terminate()
          try:p.wait(timeout=5)
          except subprocess.TimeoutExpired:p.kill();p.wait()
      for f in logs:f.close()

if __name__=='__main__':main()
