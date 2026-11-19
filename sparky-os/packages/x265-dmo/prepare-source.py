#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the edition x265 with frame packing and HandBrake's library fixes."""
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
    if version != '1:4.3-dmo1':
        raise ValueError(f'Expected x265-dmo 1:4.3-dmo1, got {version}')
    series = source / 'debian/patches/series'
    patches = sorted((recipe / 'patches').glob('*.patch'))
    for patch in patches:
        target = source / 'debian/patches' / patch.name
        if target.exists():
            raise ValueError(f'Refusing to overwrite {target}')
        shutil.copy2(patch, target)
    series.write_text(series.read_text().rstrip() + '\n' + '\n'.join(p.name for p in patches) + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=env, check=True)
    control = source / 'debian/control'
    control.write_text(control.read_text().replace('libx265-217', 'libx265-219'))
    (source / 'debian/libx265-217.install').rename(source / 'debian/libx265-219.install')
    install = source / 'debian/libx265-219.install'
    install.write_text(install.read_text().replace('.217', '.219'))
    subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', '1:4.3-dmo1+stereo3d1',
                    '--distribution', 'UNRELEASED',
                    'Carry upstream frame packing and HandBrake library fixes. Assign SONAME 219 for the additional ambient API; retain libx265-217 for existing consumers.'],
                   cwd=source, env=env, check=True)
    subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source),
                    '1:4.3-dmo1+stereo3d1+lc1', '--toolkit', str(toolkit),
                    '--build-dependency', 'bubblewrap'], cwd=source, env=env, check=True)
    reproducible.normalize_tree(source, stamp)


if __name__ == '__main__':
    main()
