# SPDX-License-Identifier: GPL-2.0-or-later
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess
import tkinter as tk
from tkinter import ttk
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'savers'))
from preferences import config_path, disabled_savers, save_disabled, read_config
from catalogue import load, Rotation
from settings import main
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
shutil.copy(source_catalogue,root/'catalogue.json')
if Path('/usr/share/gl-stereo/savers.json').exists():
    shutil.copy('/usr/share/gl-stereo/savers.json',root/'savers.json')
else:
    subprocess.run([sys.executable,str(Path(__file__).resolve().parent.parent/'savers/make-index.py'),str(root/'savers.json')],check=True)
original=tk.Tk
errors=[]; seen=[]
def create():
    window=original()
    def verify():
        try:
            def walk(parent):
                for child in parent.winfo_children():
                    yield child
                    yield from walk(child)
            widgets=list(walk(window)); tree=next(w for w in widgets if isinstance(w,ttk.Treeview))
            ids=set(tree.get_children())
            assert len(ids)==132 and 'mapscroller.pl' not in ids
            assert {'rocks','starfield','gears'} <= ids
            assert tree.item('gears','text').startswith('☐')
            tree.focus('gears'); tree.focus_force(); tree.event_generate('<space>'); window.update()
            assert tree.item('gears','text').startswith('☑')
            next(w for w in widgets if isinstance(w,ttk.Button) and w.cget('text')=='Save selection').invoke()
            seen.append(True)
        except Exception as error:
            errors.append(error); window.destroy()
    window.after(300,verify)
    return window
tk.Tk=create
main(root)
assert seen and not errors,errors
assert disabled_savers()=={'molecule'}
print('PASS: 132 saver choices, helper excluded, credits, persisted selection, disabled rotation and re-enabling; timing settings preserved')
