#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Sparky Stereo OS, ORDER 17 milestone 5: the changes to Debian's own debian/ of cloudcompare 2.13.2+git20240821+ds-7: the build
reads the person's depth limits (libstereo-declare 1.11, through Qt's X11 extras) and has the stereo window's one mode.
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
control = control.replace(old, old + ' libqt5x11extras5-dev,\n libstereo-declare-dev (>= 1.11.0),\n', 1)
Path('debian/control').write_text(control)

# libstereo-declare 1.11 (ORDER 750): the window reads the limits in the pixels of its buffer, stereo_depth_x11_get_buffer_limits, which
# calls the library's stereo_depth_x11_get_limits itself; the link gate is told the direct call was retired on purpose
Path('debian/sparky-lean-retired-stereo-imports').write_text(
    'stereo_depth_x11_get_limits the call moved to stereo_depth_x11_get_buffer_limits (libstereo-declare 1.11.0, ORDER 750: the one function that '
    'gives the limits in the buffer\'s pixels)\n')
