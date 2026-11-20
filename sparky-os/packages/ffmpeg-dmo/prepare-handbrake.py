#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare FFmpeg +17 from the published +15 source: HandBrake's fixes (+16), and Build-Depends without
libnvidia-glvkspirv (+17), so the package builds where the edition's NVIDIA pin gives that library no candidate."""
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
control.write_text(control.read_text().replace('libx265-dev (>= 1:3.5)', 'libx265-dev (>= 1:4.3-dmo1+stereo3d2+lc1)'))
subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', '10:9.0.2-dmo1+stereo3d16',
                '--distribution', 'UNRELEASED',
                'This entry holds the changes of two versions, because +stereo3d16 was staged and never published. '
                'First (+stereo3d16): import the HandBrake 1.11.2 FFmpeg fixes into the shared edition libraries; '
                'build against x265 ABI 30219.'],
               cwd=source, env=env, check=True)
nvidia = 'libchromaprint-dev <!pkg.ffmpeg.stage1>, libnvidia-glvkspirv [amd64 i386], clang [amd64 arm64]'
text = control.read_text()
assert text.count(nvidia) == 1, 'libnvidia-glvkspirv is not where +16 has it'
control.write_text(text.replace(nvidia, 'libchromaprint-dev <!pkg.ffmpeg.stage1>, clang [amd64 arm64]'))
subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', '10:9.0.2-dmo1+stereo3d17',
                '--distribution', 'UNRELEASED',
                'Second (+stereo3d17): drop libnvidia-glvkspirv [amd64 i386] from Build-Depends, inherited from deb-multimedia since its 7.x '
                'sources: nothing in the source names it (no configure test, rule or test), its package ships only '
                "NVIDIA's private versioned library, and the edition's NVIDIA pin gives it no candidate on a machine "
                'without a driver lock, so sparky-stereo-ffmpeg-fdk stopped at build-dep there. Built without it, every '
                'binary package equals +16 apart from the version: file lists, Depends, NEEDED, exported symbols, '
                '-buildconf and the lists of encoders, decoders, filters, hwaccels, bitstream filters and protocols.'],
               cwd=source, env=env, check=True)
subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source), '10:9.0.2-dmo1+stereo3d17+lc1',
                '--toolkit', str(toolkit), '--preserve-plan', str(plan)], env=env, check=True)
reproducible.normalize_tree(source, stamp)
