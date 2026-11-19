#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the HandBrake successor from deb-multimedia's source package."""
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
    args = parser.parse_args()
    source = args.source.resolve()
    stamp = reproducible.recipe_epoch([recipe])
    env = os.environ | {
        'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
        'QUILT_PATCHES': 'debian/patches',
        'PYTHONPATH': str(toolkit),
        'SOURCE_DATE_EPOCH': str(stamp),
    }
    old = subprocess.check_output(['dpkg-parsechangelog', '-SVersion'], cwd=source, text=True).strip()
    if old != '1:1.11.2-dmo3':
        raise ValueError(f'Expected handbrake-dmo 1:1.11.2-dmo3, got {old}')
    patches = sorted((recipe / 'patches').glob('*.patch'))
    series = source / 'debian/patches/series'
    for patch in patches:
        target = source / 'debian/patches' / patch.name
        if target.exists():
            raise ValueError(f'Refusing to overwrite {target}')
        shutil.copy2(patch, target)
    series.write_text(series.read_text().rstrip() + '\n' + '\n'.join(p.name for p in patches) + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=env, check=True)
    subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion',
                    '1:1.11.2-dmo3+stereo3d1', '--distribution', 'UNRELEASED',
                    'Carry upstream stereo metadata preservation and x264 frame packing; retain the deb-multimedia bundled media build.'],
                   cwd=source, env=env, check=True)
    subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source),
                    '1:1.11.2-dmo3+stereo3d1+lc1', '--toolkit', str(toolkit),
                    '--build-dependency', 'bubblewrap', '--preserve-source', 'gtk/*',
                    'GTK translation extraction and resource generators consume authored source and translator comments.'],
                   env=env, check=True)
    reproducible.normalize_tree(source, stamp)


if __name__ == '__main__':
    main()
