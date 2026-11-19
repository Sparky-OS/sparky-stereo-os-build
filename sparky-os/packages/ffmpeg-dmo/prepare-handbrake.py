#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare FFmpeg +16 from the published +15 source with HandBrake's fixes."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

recipe = Path(__file__).resolve().parent
toolkit = recipe.parents[1]
sys.path.insert(0, str(toolkit / 'repo'))
import reproducible

source = Path(sys.argv[1]).resolve()
stamp = reproducible.recipe_epoch([recipe])
env = os.environ | {'SOURCE_DATE_EPOCH': str(stamp), 'PYTHONPATH': str(toolkit),
                    'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com',
                    'QUILT_PATCHES': 'debian/patches'}
plan = source.parent / 'ffmpeg-preserve-plan.json'
version = subprocess.check_output(['dpkg-parsechangelog', '-SVersion'], cwd=source, text=True).strip()
assert version == '10:9.0.2-dmo1+stereo3d15+lc1', version
subprocess.run([sys.executable, str(toolkit / 'repo/plain-from-lc.py'), '--save-plan', str(plan), str(source)], check=True)
series = source / 'debian/patches/series'
patches = sorted((recipe / 'handbrake-patches').glob('*.patch'))
for patch in patches:
    shutil.copy2(patch, source / 'debian/patches' / patch.name)
series.write_text(series.read_text().rstrip() + '\n' + '\n'.join(p.name for p in patches) + '\n')
subprocess.run(['quilt', 'push', '-a'], cwd=source, env=env, check=True)
control = source / 'debian/control'
control.write_text(control.read_text().replace('libx265-dev,', 'libx265-dev (>= 1:4.3-dmo1+stereo3d1+lc1),'))
subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', '10:9.0.2-dmo1+stereo3d16',
                '--distribution', 'UNRELEASED',
                'Import the HandBrake 1.11.2 FFmpeg fixes into the shared edition libraries; build against x265 ABI 219.'],
               cwd=source, env=env, check=True)
subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source), '10:9.0.2-dmo1+stereo3d16+lc1',
                '--toolkit', str(toolkit), '--preserve-plan', str(plan)], env=env, check=True)
reproducible.normalize_tree(source, stamp)
