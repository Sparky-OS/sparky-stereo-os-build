#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Installed units' documentation and the new wait message in nine catalogs.
Run in a container with the package installed; argument: authored problems-lang.
"""
from pathlib import Path
import os
import re
import subprocess
import sys

assert Path('/.dockerenv').exists()
fail=0
for name in ['sparky-stereo-opengl-default.service','sparky-stereo-hardware-nvidia-i386.service']:
    unit=Path('/usr/lib/systemd/system')/name
    targets=re.findall(r'^Documentation=file:(.*)$',unit.read_text(),re.M)
    good=len(targets)==1 and Path(targets[0]).is_file() and Path(targets[0]).stat().st_size>0
    if good:
        owner=subprocess.run(['dpkg-query','-S',targets[0]],capture_output=True,text=True)
        good=owner.returncode==0 and owner.stdout.startswith('sparky-stereo-hardware: ')
    print(('PASS ' if good else 'FAIL ')+name+': documentation shipped by this package')
    fail+=not good
for lang in ['en','pl','pt_BR','fr','de','ja','ko','zh_CN','zh_TW']:
    expected=re.search(r'^LOCAL16="(.*)"$',(Path(sys.argv[1])/lang).read_text(),re.M).group(1)
    p=subprocess.run(['sparky-stereo-problems','say','sparky-stereo-hardware','LOCAL16'],env=dict(os.environ,LANGUAGE=lang,LANG='en_US.UTF-8',LC_ALL='en_US.UTF-8'),capture_output=True,text=True)
    good=p.returncode==0 and expected in p.stdout+p.stderr
    print(('PASS ' if good else 'FAIL ')+lang+': installed LOCAL16 exactly matches authored translation')
    fail+=not good
sys.exit(bool(fail))
