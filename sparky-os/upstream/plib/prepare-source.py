#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Extend the published plib source with per-draw screen planes and infinity."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

recipe = Path(__file__).resolve().parent
os_tree = recipe.parents[1]
name = recipe.name
base = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
expected = {'plib': '170ecf3258135ac60aeb5b187ff49e9c9fa2841a709621d46a7a3d88e720abb8',
            'torcs': '7be53478c89db9dc8815d905353231b84bc5d206057c39a7a8e864c55c364dda'}
assert hashlib.sha256(base.read_bytes()).hexdigest() == expected[name], 'unexpected published descriptor'
assert os.environ['SOURCE_DATE_EPOCH'].isdigit()
out.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix=name+'-source-', dir=out.parent) as temp:
    work = Path(temp)
    subprocess.run(['dpkg-source', '--skip-patches', '-x', str(base), str(work/'published')], check=True)
    overlay = work/'overlay'
    (overlay/'patches').mkdir(parents=True)
    series = (work/'published/debian/patches/series').read_text().rstrip()+'\n'
    for patch in (recipe/'series').read_text().splitlines():
        assert patch not in series.splitlines(), patch
        shutil.copy2(recipe/'patches'/patch, overlay/'patches'/patch)
        series += patch+'\n'
    (overlay/'patches/series').write_text(series)
    if name == 'torcs':
        control = (work/'published/debian/control').read_text()
        assert control.count('libplib-dev,') == 1
        control = control.replace('libplib-dev,', 'libplib-dev (>= 1.8.5-15+stereo3d3+lc1),')
        assert control.count('         ${shlibs:Depends}') == 1
        control = control.replace('         ${shlibs:Depends}',
                                  '         libplib1t64 (>= 1.8.5-15+stereo3d3+lc1), ${shlibs:Depends}')
        (overlay/'control').write_text(control)
    version = {'plib':'1.8.5-15+stereo3d3','torcs':'1.3.7+dfsg-5+stereo3d3'}[name]
    item = ('Expose per-draw screen planes and infinite backgrounds, retaining environment overrides.' if name == 'plib'
            else 'Select changeable driver and chase screen planes; preserve the owning Xrandr link correction.')
    subprocess.run(['python3', str(os_tree/'repo/lc-successor.py'), '--in-place', '--next', version,
                    '--item', item, '--overlay', str(overlay), '--work', str(work), str(base), str(out)], check=True)
    for archive in base.parent.glob(name+'_*.orig.tar.*'):
        shutil.copyfile(archive, out/archive.name)
