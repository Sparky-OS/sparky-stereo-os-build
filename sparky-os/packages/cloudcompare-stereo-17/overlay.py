#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Sparky Stereo OS, ORDER 17 milestone 5: the changes to Debian's own debian/ of cloudcompare 2.13.2+git20240821+ds-7: the build
reads the person's depth limits (libstereo-declare 1.10, through Qt's X11 extras) and has the stereo window's one mode.
Run in the unpacked source. Every replace states what it expects and stops when Debian's file is not the one this was written for."""
from pathlib import Path

rules = Path('debian/rules').read_text()
old = '\t\t-DOPTION_USE_GDAL=ON \\\n'
assert old in rules, 'Debian rules changed'
rules = rules.replace(old, old + '\t\t-DOPTION_STEREO_DECLARE=ON \\\n', 1)
Path('debian/rules').write_text(rules)

control = Path('debian/control').read_text()
old = ' libqt5opengl5-dev,\n'
assert old in control, 'Debian control changed'
control = control.replace(old, old + ' libqt5x11extras5-dev,\n libstereo-declare-dev (>= 1.10.0),\n', 1)
Path('debian/control').write_text(control)
