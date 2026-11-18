#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
import configparser
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlparse, unquote

case = Path(os.environ['CASE'])
home = Path.home()
desktop = Path(subprocess.check_output(['xdg-user-dir', 'DESKTOP'], text=True).strip())
checks = []
labels = json.loads((case / 'kde-home-labels.json').read_text())
found = {}
for path in desktop.iterdir():
    if path.suffix != '.desktop':
        continue
    p = configparser.ConfigParser(interpolation=None)
    p.read(path)
    if not p.has_section('Desktop Entry'):
        continue
    entry = p['Desktop Entry']
    url = entry.get('URL', '')
    if url.rstrip('/') == 'trash:':
        found['trash'] = path
    if urlparse(url).scheme == 'file' and Path(unquote(urlparse(url).path)) == home:
        found['home'] = path
        checks.append(('home icon', entry.get('Icon') == 'user-home'))
        for language, wanted in labels.items():
            key = 'Name' if language == 'en' else f'Name[{language}]'
            checks.append((f'KDE home label {language}', entry.get(key) == wanted))
checks.extend([('Trash desktop link', 'trash' in found), ('Home desktop link', 'home' in found)])
result = dict(checks=[dict(name=name, passed=passed) for name, passed in checks], files={k:str(v) for k,v in found.items()})
(case / 'desktop-check.json').write_text(json.dumps(result, indent=2) + '\n')
for name, passed in checks:
    print('PASS' if passed else 'FAIL', name, flush=True)
# Retain the authored user files and one-shot state before the rig removes its private home.
if 'trash' in found and 'home' in found:
    subprocess.run(['python3', '/rig-scripts/login-splash/shot.py', 'Virtual-0', str(case / 'desktop-shortcuts.png')], check=True)
    before = {k:p.read_bytes() for k,p in found.items()}
    found['trash'].unlink()
    subprocess.run(['/usr/lib/sparky-stereo-look/first-login-desktop-shortcuts'], check=True)
    checks.append(('a removed Trash stays removed', not found['trash'].exists()))
    checks.append(('the retained Home is unchanged', found['home'].read_bytes() == before['home']))
    for name, passed in checks[-2:]: print('PASS' if passed else 'FAIL', name, flush=True)
    result['removalChecks'] = [dict(name=name, passed=passed) for name,passed in checks[-2:]]
    found['home'].unlink()
    subprocess.run(['/usr/lib/sparky-stereo-look/first-login-desktop-shortcuts'], check=True)
    checks.append(('a removed Home stays removed', not found['home'].exists()))
    print('PASS' if checks[-1][1] else 'FAIL', checks[-1][0], flush=True)
    result['removalChecks'].append(dict(name=checks[-1][0], passed=checks[-1][1]))
    (case / 'desktop-check.json').write_text(json.dumps(result, indent=2) + '\n')
raise SystemExit(0 if all(passed for _,passed in checks) else 1)
