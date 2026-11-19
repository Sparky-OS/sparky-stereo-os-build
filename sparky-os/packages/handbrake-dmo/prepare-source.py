#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare fork source using Debian's shared-library route and DMO's features."""
import json
import os
from pathlib import Path
import subprocess
import sys

recipe = Path(__file__).resolve().parent
toolkit = recipe.parents[1]
sys.path.insert(0, str(toolkit / 'repo'))
import reproducible

source = Path(sys.argv[1]).resolve()
stamp = reproducible.recipe_epoch([recipe])
info = json.loads((source / 'debian/sparky-fork-source.json').read_text())
version = '1:' + info['upstream_version'] + '-dmo3+stereo3d1'
env = os.environ | {'SOURCE_DATE_EPOCH': str(stamp), 'PYTHONPATH': str(toolkit),
                    'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com'}
control = source / 'debian/control'
t = control.read_text()
t = t.replace('libx264-dev (>= 3:0.155~)', 'libx264-dev (>= 4:0.165.3222+gitb35605a-dmo5+stereo3d1+lc1)')
t = t.replace(' libmp3lame-dev,',
              ' libavcodec-dev (>= 10:9.0.2-dmo1+stereo3d16+lc1), libavformat-dev (>= 10:9.0.2-dmo1+stereo3d16+lc1),\n'
              ' libavfilter-dev, libavutil-dev, libswscale-dev, libswresample-dev, libdvdread-dev,\n'
              ' libx265-dev (>= 1:4.3-dmo1+stereo3d1+lc1), zlib1g-dev, libmp3lame-dev,')
control.write_text(t)
rules = source / 'debian/rules'
t = rules.read_text()
# The fork keeps upstream's GNU tuple parser rather than DMO's vendorless parser.
t = t.replace('--host=$(DEB_HOST_GNU_TYPE)', '--host=$(DEB_HOST_GNU_TYPE:%-linux-gnu=%-unknown-linux-gnu)')
t = t.replace('--build=$(DEB_BUILD_GNU_TYPE)', '--build=$(DEB_HOST_GNU_TYPE:%-linux-gnu=%-unknown-linux-gnu)')
rules.write_text(t)
subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', version,
                '--distribution', 'UNRELEASED',
                'Build the Sparky-OS HandBrake fork against shared edition libraries, preserving all three binary names and encoder features.'],
               cwd=source, env=env, check=True)
subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source), version + '+lc1', '--toolkit', str(toolkit),
                '--build-dependency', 'bubblewrap', '--preserve-source', 'gtk/*',
                'GTK translation and resource generators consume authored source and translator comments.'], env=env, check=True)
reproducible.normalize_tree(source, stamp)
