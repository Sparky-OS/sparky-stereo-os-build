#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Extend the published TORCS source (+stereo3d3) so that the game starts in stereo."""
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
            'torcs': '48f29785300da745759f5ae57500ce9b5a83cb5f3b1947beedb2bf5d5ac49550'}
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
    version = {'plib':'1.8.5-15+stereo3d3','torcs':'1.3.7+dfsg-5+stereo3d4'}[name]
    item = ('Expose per-draw screen planes and infinite backgrounds, retaining environment overrides.' if name == 'plib'
            else 'Start in stereo unless the person chose otherwise; ask for a stereo drawable only where the display offers one.')
    subprocess.run(['python3', str(os_tree/'repo/lc-successor.py'), '--in-place', '--next', version,
                    '--item', item, '--overlay', str(overlay), '--work', str(work), str(base), str(out)], check=True)
    for archive in base.parent.glob(name+'_*.orig.tar.*'):
        shutil.copyfile(archive, out/archive.name)
