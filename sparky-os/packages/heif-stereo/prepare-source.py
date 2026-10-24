#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Apply the HEIF stereo reader changes to the recorded Debian source baselines."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('project', choices=['libheif', 'kf6-kimageformats', 'kf6-kfilemetadata'])
parser.add_argument('source', type=Path)
parser.add_argument('version')
args = parser.parse_args()
source = args.source.resolve()
recipe = Path(__file__).resolve().parent
patch = {'libheif': 'libheif-stem.patch', 'kf6-kimageformats': 'kimageformats-stem.patch', 'kf6-kfilemetadata': 'kfilemetadata-stem.patch'}[args.project]
env = os.environ | {'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com', 'QUILT_PATCHES': 'debian/patches'}
if args.project == 'libheif':
    toolkit = recipe.parents[1]
    subprocess.run(['python3', '-m', 'lean.debian_prepare', str(source), args.version, '--toolkit', str(toolkit)],
                   env=env | {'PYTHONPATH': str(toolkit)}, check=True)
else:
    if 'lean.source_tree project' not in (source / 'debian/rules').read_text():
        raise ValueError('Use the published native Lean Code source baseline')
    subprocess.run(['dch', '--newversion', args.version, '--distribution', 'UNRELEASED',
                    'Read ster and stem entity groups through libheif, preserving the primary monoscopic fallback and complete stereo views.'], cwd=source, env=env, check=True)
destination = source / 'debian/patches' / patch
destination.parent.mkdir(exist_ok=True)
if destination.exists():
    raise ValueError('Refusing to replace an existing HEIF patch')
shutil.copy2(recipe / 'patches' / patch, destination)
with (source / 'debian/patches/series').open('a') as stream:
    stream.write(patch + '\n')
subprocess.run(['quilt', 'push'], cwd=source, env=env, check=True)
if args.project != 'libheif':
    path = source / 'debian/control'
    control = path.read_text()
    dependency = 'libheif-dev (>= 1.23.6-2+stereo3d1+lc1)'
    if args.project == 'kf6-kimageformats':
        control = re.sub(r'libheif-dev \([^)]*\)', dependency, control)
        control = control.replace('Depends: libheif-plugin-j2kdec,', 'Depends: libheif1 (>= 1.23.6-2+stereo3d1+lc1),\n         libheif-plugin-j2kdec,')
        control = control.replace('Breaks: kf6-kimageformat-plugins,', 'Breaks: libstereo-layer1 (<< 1.11.0-1+lc1),\n        kf6-kimageformat-plugins,')
    else:
        control = control.replace('Build-Depends:', 'Build-Depends: ' + dependency + ',')
        control = control.replace('Package: libkf6filemetadata-bin\n', 'Package: libkf6filemetadata-bin\n')
        # The module containing the libheif calls is shipped by this binary package.
        package = control.index('Package: libkf6filemetadata-bin\n')
        head, tail = control[:package], control[package:]
        tail = tail.replace('Depends:', 'Depends: libheif1 (>= 1.23.6-2+stereo3d1+lc1),', 1)
        control = head + tail
    path.write_text(control)

if args.project != 'libheif':
    fixtures = source / ('autotests/depth/heif-stem' if args.project == 'kf6-kimageformats' else 'autotests/samplefiles/stereo/depth/heif-stem')
    fixtures.mkdir(parents=True, exist_ok=True)
    paths = []
    for asset in (recipe / 'fixtures').iterdir():
        if asset.suffix in ('.heic', '.png'):
            shutil.copy2(asset, fixtures / asset.name)
            paths.append(str((fixtures / asset.name).relative_to(source)))
    with (source / 'debian/source/include-binaries').open('a') as output:
        output.write('\n'.join(paths) + '\n')
