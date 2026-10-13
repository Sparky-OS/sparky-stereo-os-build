# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path('savers').resolve()))
from catalogue import receipt, eligible

lib = str(Path('libgl-stereo.so').resolve())
entries=[]
root=Path('out/eligibility'); root.mkdir(parents=True,exist_ok=True)
# Receipts are written only after the separate pixel tests pass.
for name in ('starfield','rocks'):
    proof=json.loads(Path(f'out/{name}/proof.json').read_text())
    command=[str(Path('savers/starfield' if name=='starfield' else 'out/bin/rocks').resolve())]
    environment={}
    if name=='rocks': command += ['-window','-geometry','640x360','-sbs']
    else: environment=dict(GL_STEREO='1', LD_PRELOAD=lib)
    entries.append(receipt(name,command,environment,proof,lib))

candidates={
    'gears':['/usr/libexec/xscreensaver/gears','-window'],
    'molecule':['/usr/libexec/xscreensaver/molecule','-window','-no-shells','-no-labels','-no-titles'],
    'rubik':['/usr/libexec/xscreensaver/rubik','-window'],
}
for name,command in candidates.items():
    directory=root/name; directory.mkdir(exist_ok=True)
    for old in directory.glob('frame-*'): old.unlink()
    (directory/'result.json').unlink(missing_ok=True)
    profile=dict(GL_STEREO='1', LD_PRELOAD=lib, GL_STEREO_SEPARATION='1', GL_STEREO_CONVERGENCE='1')
    env=dict(os.environ, **profile, GL_STEREO_DUMP='30',GL_STEREO_DUMP_DIR=str(directory.resolve()))
    with (directory/'producer.log').open('w') as output:
        run=subprocess.run(['timeout','--foreground','4',*command,'-geometry','640x360'],env=env,stdout=output,stderr=output)
    if run.returncode not in (0,124):
        print(name,'excluded: producer failure',run.returncode); continue
    with (directory/'oracle.log').open('w') as output:
        result=subprocess.run([sys.executable,'measure-hack.py',str(directory),'--comfort'],stdout=output,stderr=output)
    if result.returncode:
        print(name,'excluded: stereo/comfort oracle failure'); continue
    proof=json.loads((directory/'result.json').read_text())
    entries.append(receipt(name,[*command,'-geometry','640x360'],profile,proof,lib))
    print(name,'qualified',proof['disparity_bounds_px'])
assert all(eligible(entry) for entry in entries)
(root/'catalogue.json').write_text(json.dumps(entries,indent=2))
print('Qualified rotation:',[entry['id'] for entry in entries])
