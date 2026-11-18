#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
import json
import os
from pathlib import Path
import subprocess
import tempfile

checks = {}
with tempfile.TemporaryDirectory(dir=os.environ['CASE'], prefix='account-') as temporary:
    home = Path(temporary)
    env = os.environ | dict(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'), LANG='en_US.UTF-8')
    subprocess.run(['xdg-user-dirs-update'], env=env, check=True)
    desktop = home / 'Desktop'
    desktop.mkdir(exist_ok=True)
    # An existing account without links gets them once even though Desktop already exists.
    subprocess.run(['/usr/lib/sparky-stereo-look/first-login-desktop-shortcuts'], env=env, check=True)
    checks['existing account gets both links'] = (desktop / 'trash.desktop').exists() and (desktop / 'home.desktop').exists()
    for p in desktop.iterdir(): p.unlink()
    subprocess.run(['/usr/lib/sparky-stereo-look/first-login-desktop-shortcuts'], env=env, check=True)
    checks['removed links stay removed'] = not list(desktop.iterdir())
with tempfile.TemporaryDirectory(dir=os.environ['CASE'], prefix='choices-') as temporary:
    home = Path(temporary)
    env = os.environ | dict(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'), LANG='en_US.UTF-8')
    subprocess.run(['xdg-user-dirs-update'], env=env, check=True)
    desktop = home / 'Desktop'
    desktop.mkdir(exist_ok=True)
    trash = '[Desktop Entry]\nType=Link\nName=My bin\nIcon=user-trash-full\nURL=trash:/\n'
    link = f'[Desktop Entry]\nType=Link\nName=My files\nIcon=folder\nURL={home.as_uri()}\n'
    (desktop / 'personal-bin.desktop').write_text(trash)
    (desktop / 'personal-files.desktop').write_text(link)
    subprocess.run(['/usr/lib/sparky-stereo-look/first-login-desktop-shortcuts'], env=env, check=True)
    checks['existing personal links are not duplicated'] = len(list(desktop.iterdir())) == 2
    checks['personal labels and icons kept'] = (desktop / 'personal-bin.desktop').read_text() == trash and (desktop / 'personal-files.desktop').read_text() == link
with tempfile.TemporaryDirectory(dir=os.environ['CASE'], prefix='collision-') as temporary:
    home = Path(temporary)
    env = os.environ | dict(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'), XDG_STATE_HOME=str(home / '.local/state'), LANG='en_US.UTF-8')
    subprocess.run(['xdg-user-dirs-update'], env=env, check=True)
    desktop = home / 'Desktop'
    desktop.mkdir(exist_ok=True)
    personal = '[Desktop Entry]\nType=Link\nName=Other place\nURL=file:///tmp\n'
    (desktop / 'home.desktop').write_text(personal)
    subprocess.run(['/usr/lib/sparky-stereo-look/first-login-desktop-shortcuts'], env=env, check=True)
    checks['same filename preserves personal file'] = (desktop / 'home.desktop').read_text() == personal and (desktop / 'home-1.desktop').exists()
print(json.dumps(checks, indent=2))
raise SystemExit(0 if all(checks.values()) else 1)
