# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'savers'))
from preferences import config_path, disabled_savers, flat_savers, save_disabled, read_config
from catalogue import load, Rotation
root=Path('out/saver-preferences').resolve(); root.mkdir(parents=True,exist_ok=True)
installed=Path('/usr/share/gl-stereo/catalogue.json')
source_catalogue=installed if installed.exists() else Path('out/eligibility/catalogue.json')
os.environ['LC_ALL']='C'
os.environ['XDG_CONFIG_HOME']=str(root/'config')
config_path().parent.mkdir(exist_ok=True)
config_path().write_text('[General]\nIdleSeconds=8100\nCycleSeconds=600\n[Other]\nKeep=yes\n')
save_disabled({'gears','molecule'})
assert disabled_savers()=={'gears','molecule'}
assert read_config().getint('General','IdleSeconds')==8100
assert read_config().get('Other','Keep')=='yes'
entries=load(source_catalogue)
rotation=Rotation(entries)
assert {rotation.next({'gears','molecule'})['id'] for _ in range(3*len(entries))} == {e['id'] for e in entries}-{'gears','molecule'}
assert rotation.next({e['id'] for e in entries}) is None
assert {rotation.next()['id'] for _ in range(3*len(entries))}=={e['id'] for e in entries}
# the list of savers is System Settings' Screensavers page now; the store it writes is the one tested here
save_disabled({'molecule'})
assert disabled_savers()=={'molecule'}
assert read_config().getint('General','IdleSeconds')==8100 and read_config().get('Other','Keep')=='yes'
assert flat_savers()==set()
with config_path().open('a') as out: out.write('')
text=config_path().read_text().replace('[General]\n','[General]\nFlatSavers=deco, maze\n',1)
config_path().write_text(text)
assert flat_savers()=={'deco','maze'} and disabled_savers()=={'molecule'}
print('PASS: persisted selection, disabled rotation and re-enabling, the ticked 2D savers; timing settings preserved')
