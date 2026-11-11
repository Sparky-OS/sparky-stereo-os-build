#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare DXVK +5 from the retained +3 source and the reviewed patches."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'repo'))
import reproducible


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--toolkit', type=Path, required=True)
    args = parser.parse_args()
    source, toolkit = args.source.resolve(), args.toolkit.resolve()
    recipe = Path(__file__).resolve().parent
    stamp = reproducible.recipe_epoch([recipe])
    env = os.environ | {'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
                        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
                        'QUILT_PATCHES': 'debian/patches', 'PYTHONPATH': str(toolkit)}
    old = subprocess.check_output(['dpkg-parsechangelog', '-SVersion'], cwd=source, text=True).strip()
    if old != '2.7.1-4+stereo3d3+lc1' or (source / '.sparky-lc').exists():
        raise ValueError('Expected a fresh extraction of the retained DXVK +3 descriptor')
    plan = source.with_name(source.name + '.published-preserve.json')
    upstream = ('stereo3d/0000-upstream-d3d11-resize-dimensions.patch',
                'upstream-d3d11-resize-dimensions.patch')
    patches = [upstream,
               ('stereo3d/0006-packed-eye-exact-copy.patch', 'packed-eye-exact-copy.patch'),
               ('stereo3d/0007-wine-wsi-v1-request.patch', 'wine-wsi-v1-request.patch')]
    for name, authored in patches:
        if (source / 'debian/patches' / name).exists():
            raise ValueError('Refusing to replace a patch')
        subprocess.run(['patch', '--dry-run', '--fuzz=0', '-p1', '-i', str(recipe / 'patches' / authored)], cwd=source, check=True)
    # This descriptor predates the adapter's dependency-prefix convention.
    control = source / 'debian/control'
    text = control.read_text()
    suffix = ', gcc, node-acorn, nodejs, perl, python3, python3-yaml\n'
    if text.count(suffix) != 1 or 'Build-Depends: debhelper-compat (= 13),' not in text:
        raise ValueError('Review changed legacy LC build dependencies')
    text = text.replace(suffix, '\n').replace(
        'Build-Depends:', 'Build-Depends: gcc, node-acorn, nodejs, perl, python3, python3-yaml,', 1)
    control.write_text(text)
    subprocess.run([sys.executable, str(toolkit / 'repo/plain-from-lc.py'), '--save-plan', str(plan), str(source)], env=env, check=True)
    subprocess.run(['quilt', 'pop', '-a'], cwd=source, env=env, check=True)
    for name, authored in patches:
        shutil.copy2(recipe / 'patches' / authored, source / 'debian/patches' / name)
    series = source / 'debian/patches/series'
    series.write_text(upstream[0] + '\n' + series.read_text().rstrip() + '\n' +
                      '\n'.join(name for name, _ in patches[1:]) + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=env, check=True)
    subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', '2.7.1-4+stereo3d5', '--distribution', 'unstable',
                    'Backport ficool2 upstream commit 3dbf33cb2205dd0d573cbc7a65e3855d97a4800b to use the requested swapchain resize dimensions. Retain exact packed-eye copies, the versioned Wine child-surface contract and ordinary WSI fallback.'], cwd=source, env=env, check=True)
    subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source), '2.7.1-4+stereo3d5+lc1', '--toolkit', str(toolkit), '--build-dependency', 'bubblewrap', '--preserve-plan', str(plan)], env=env | {'SOURCE_DATE_EPOCH': str(stamp)}, check=True)
    reproducible.normalize_tree(source, stamp)


if __name__ == '__main__':
    main()
