import sys, os, time, subprocess, json, pathlib, struct
sys.path.insert(0,'/rig')
import proof

def run(args,timeout=10):
    p=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
    return dict(command=args,exit=p.returncode,stdout=p.stdout,stderr=p.stderr)
def tick(pid):
    s=pathlib.Path('/proc/%s/stat'%pid).read_text().split(') ')[1].split()
    return int(s[11])+int(s[12])
def node_states():
    return [dict(name=o['info']['props'].get('node.name'),state=o['info']['state'],format=o['info']['params'].get('Format')) for o in proof.dump() if o['type']=='PipeWire:Interface:Node']
track=b'\x00\xc0\x00\x00\x90\x3c\x64\x83\x60\x80\x3c\x00\x00\xff\x2f\x00'
pathlib.Path('/tmp/am735.mid').write_bytes(b'MThd'+struct.pack('>IHHH',6,0,1,480)+b'MTrk'+struct.pack('>I',len(track))+track)
result={'label':sys.argv[1], 'ports':run(['pw-link','-io']), 'alsa':run(['aplaymidi','-l']), 'initial_nodes':node_states()}
# No synth port is installed by either baseline. Play without a chosen target, then inspect the capture.
for p in pathlib.Path('/run/sa631').glob('dac.raw*'): p.unlink()
result['midi_default']=run(['timeout','3','pw-midiplay','/tmp/am735.mid'])
raw=pathlib.Path('/run/sa631/dac.raw')
result['default_capture_bytes']=raw.stat().st_size if raw.exists() else 0
if sys.argv[1]=='stock-fluidsynth':
    p=subprocess.Popen(['fluidsynth','-nis','-a','pipewire','-r','48000','/usr/share/sounds/sf2/TimGM6mb.sf2'],stdout=open('/tmp/stock-synth.log','w'),stderr=subprocess.STDOUT)
    try:
        time.sleep(3)
        result['synth_alive']=p.poll() is None
        result['idle_nodes']=node_states()
        if p.poll() is None:
            start=tick(p.pid); begin=time.monotonic(); time.sleep(3)
            result['idle_cpu_percent']=100*(tick(p.pid)-start)/os.sysconf('SC_CLK_TCK')/(time.monotonic()-begin)
            result['rss_kib']=int(next(l.split()[1] for l in pathlib.Path('/proc/%s/status'%p.pid).read_text().splitlines() if l.startswith('VmRSS:')))
            result['rates_with_idle_synth']=[proof.row(r,'dac',3) for r in (44100,96000)]
    finally:
        p.terminate();p.wait(timeout=10)
    result['synth_log']=pathlib.Path('/tmp/stock-synth.log').read_text()
else:
    result['rates_without_synth']=[proof.row(r,'dac',3) for r in (44100,96000)]
print(json.dumps(result,indent=2))
