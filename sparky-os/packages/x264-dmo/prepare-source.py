#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the edition x264 with frame packing and HandBrake's library fixes."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

recipe = Path(__file__).resolve().parent
toolkit = recipe.parents[1]
sys.path.insert(0, str(toolkit / 'repo'))
import reproducible


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    source = parser.parse_args().source.resolve()
    stamp = reproducible.recipe_epoch([recipe])
    env = os.environ | {'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
                        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
                        'QUILT_PATCHES': 'debian/patches', 'PYTHONPATH': str(toolkit),
                        'SOURCE_DATE_EPOCH': str(stamp)}
    version = subprocess.check_output(['dpkg-parsechangelog', '-SVersion'], cwd=source, text=True).strip()
    if version != '3:0.165.3222+gitb35605a-dmo5':
        raise ValueError(f'Expected x264-dmo 3:0.165.3222+gitb35605a-dmo5, got {version}')
    series = source / 'debian/patches/series'
    patches = sorted((recipe / 'patches').glob('*.patch'))
    for patch in patches:
        target = source / 'debian/patches' / patch.name
        if target.exists():
            raise ValueError(f'Refusing to overwrite {target}')
        shutil.copy2(patch, target)
    series.write_text(series.read_text().rstrip() + '\n' + '\n'.join(p.name for p in patches) + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=env, check=True)
    subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', '3:0.165.3222+gitb35605a-dmo5+stereo3d1',
                    '--distribution', 'UNRELEASED',
                    'Carry HandBrake stack-alignment build compatibility in the edition shared x264.'],
                   cwd=source, env=env, check=True)
    subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source),
                    '3:0.165.3222+gitb35605a-dmo5+stereo3d1+lc1', '--toolkit', str(toolkit),
                    '--build-dependency', 'bubblewrap'], cwd=source, env=env, check=True)
    reproducible.normalize_tree(source, stamp)


if __name__ == '__main__':
    main()
