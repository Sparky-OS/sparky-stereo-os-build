from pathlib import Path
import json,os,sys,time,subprocess,shutil
out=Path(sys.argv[1]);pid=int(sys.argv[2]);videos=Path(os.environ['HOME'])/'Videos'
def wait(predicate):
 until=time.monotonic()+120
 while time.monotonic()<until:
  os.kill(pid,0)
  if predicate():return
  time.sleep(.2)
 raise RuntimeError('Baseline did not acknowledge recording or complete it')
def action(serial,checked=False,inspect=False):
 p=out/'action.pending';p.write_text(json.dumps(dict(serial=serial,checked=checked,recording=True,inspect=inspect)));p.replace(out/'action.request')
 def ack():
  p=out/'action.response'
  if not p.exists():return False
  r=json.loads(p.read_text());return r['serial']==serial and (inspect or r['checked']==checked) and r['invoked']
 wait(ack)
 shutil.copy2(out/'action.response',out/f'action-{serial}.json')
 return json.loads((out/'action.response').read_text())
wait(lambda:'Processing counter reset' in (out/'kamoso.log').read_text(errors='replace'))
def preview_ready():
 p=out/'pipeline.json'
 if not p.exists():return False
 rows=json.loads(p.read_text())
 return any(r['factory']==os.environ.get('KAM61_PREVIEW_FACTORY','qml6glsink') and r.get('sinkBuffers',0)>=5 for r in rows)
wait(preview_ready)
shutil.copy2(out/'pipeline.json',out/'preview-pipeline.json')
initial=action(1,inspect=True)
action(2,True)
assert not action(3,True)['triggered'], "Already recording must not toggle"
time.sleep(8)
shutil.copy2(out/'pipeline.json',out/'record-pipeline.json')
action(4,False)
assert not action(5,False)['triggered'], "Already stopped must not toggle"
wait(lambda:'Camerabin now idle' in (out/'kamoso.log').read_text(errors='replace') or 'video-done' in (out/'kamoso.log').read_text(errors='replace'))
films=list(videos.glob('*.mkv'));assert len(films)==1,films
p=out/'ordinary.ogv';shutil.copy2(films[0],p)
with (out/'probe.json').open('w') as f:subprocess.run(['ffprobe','-v','error','-show_format','-show_streams','-of','json',str(p)],stdout=f,check=True)
print((out/'probe.json').read_text())
