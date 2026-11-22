#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Only in the disposable container: synthetic catalogue and daemon boundary."""
from pathlib import Path
import hashlib,json,shutil,os
out=Path('/out')/os.environ.get('LC73_CASE','amd-100');out.mkdir(parents=True,exist_ok=True);os.chown(out,1000,1000)
exe=Path('/usr/bin/captiond')
if not Path('/usr/bin/captiond.real').exists():exe.rename('/usr/bin/captiond.real')
shutil.copyfile('/proof/installed-stand-in.py',exe);exe.chmod(0o755)
cat=Path('/usr/share/sparky-stereo/live-captions/models.json');original=cat.read_bytes();(out/'original-models.json').write_bytes(original)
model=Path('/home/builder/.local/share/captiond/models/ggml-tiny.bin');model.parent.mkdir(parents=True,exist_ok=True);model.write_text('Synthetic path witness, not a speech model. Never load.\n')
data=json.loads(original);data[0]['bytes']=model.stat().st_size;data[0]['sha256']=hashlib.sha256(model.read_bytes()).hexdigest();cat.write_text(json.dumps(data)+'\n');(out/'fixture-models.json').write_bytes(cat.read_bytes())
(out/'fixture-boundary.json').write_text(json.dumps({'replaced':['/usr/bin/captiond',str(cat)],'unchanged':['/usr/bin/kaption','/usr/bin/sparky-stereo-live-captions','Partners KCM and command','installed user unit'],'model':str(model),'model_bytes':model.stat().st_size,'model_loaded':False},indent=2)+'\n')
conf=Path('/home/builder/.config/pipewire/pipewire.conf.d');conf.mkdir(parents=True,exist_ok=True)
(conf/'90-lc73.conf').write_text('''context.objects = [
{ factory = adapter args = { factory.name = support.null-audio-sink node.name = captiond-test-sink node.description = "Caption test sink" media.class = Audio/Sink audio.position = [ FL FR ] adapter.auto-port-config = { mode = dsp monitor = true position = preserve } } }
{ factory = adapter args = { factory.name = support.null-audio-sink node.name = captiond-test-source node.description = "Caption test source" media.class = Audio/Source audio.position = [ MONO ] adapter.auto-port-config = { mode = dsp monitor = true position = preserve } } }
]''')
for tree in ['/home/builder/.local','/home/builder/.config']:
 for parent,dirs,files in os.walk(tree):
  os.chown(parent,1000,1000)
  for name in files:os.chown(Path(parent)/name,1000,1000)

unit=Path("/etc/systemd/user/lc73-session.target");unit.write_text("[Unit]\nDescription=Disposable graphical login fixture\nRequires=graphical-session.target\nAfter=graphical-session.target\n")

if os.environ.get('LC73_KIT_FIXTURE')=='1':
 data=json.loads(cat.read_text())
 for entry in data:
  target=model.parent/entry['file'];target.write_bytes(model.read_bytes());os.chown(target,1000,1000)
  entry['bytes']=target.stat().st_size;entry['sha256']=hashlib.sha256(target.read_bytes()).hexdigest()
 cat.write_text(json.dumps(data)+'\n')
 shutil.copyfile('/proof/kit-vibe-fixture.py','/usr/bin/vibe-server');os.chmod('/usr/bin/vibe-server',0o755)
