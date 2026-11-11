#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# ORDER 43: no image list names a package that runs on one CPU vendor only (thermald: Intel) or on data-centre NVLink
# systems only (nvidia-imex), and no list names urfkill; sparky-stereo-hardware's detection installs thermald on Intel.
# Run from anywhere: python3 cpu-vendor-services-test.py   Exit 1 on any FAIL.
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LISTS = os.path.join(HERE, '..')
NOT_LISTED = ('thermald', 'nvidia-imex', 'urfkill', 'liburfkill-glib0')
failed = 0


def check(ok, what):
    global failed
    print(('PASS ' if ok else 'FAIL ') + what)
    failed += not ok


for path in sorted(glob.glob(os.path.join(LISTS, '*.list'))):
    names = {l.strip() for l in open(path) if l.strip() and not l.startswith('#')}
    for name in NOT_LISTED:
        check(name not in names, f'{os.path.basename(path)} does not name {name}')
source = open(os.path.join(LISTS, 'make-lists.py')).read()
for name in NOT_LISTED:
    check(not re.search(r"'%s'" % re.escape(name), source), f"make-lists.py does not list '{name}'")
detect = open(os.path.join(LISTS, '..', 'packages', 'sparky-stereo-hardware', 'lib', 'detect.py')).read()
check('packages.add("thermald")' in detect and 'vendor == "GenuineIntel"' in detect, 'detect.py adds thermald for GenuineIntel')
sys.exit(1 if failed else 0)
