#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Extend Gwenview's existing native Lean Code source with per-file eye correction."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('version')
args = parser.parse_args()
source = args.source.resolve()
recipe = Path(__file__).resolve().parent
rules = (source / 'debian/rules').read_text()
for required in ('lean.source_tree project', 'lean.source_tree restore', 'lean.debhelper'):
    if required not in rules:
        raise ValueError('Use the already integrated edition Gwenview source package')
patch = 'stereo-per-file-swap.patch'
destination = source / 'debian/patches' / patch
if destination.exists():
    raise ValueError('Refusing to replace an existing Gwenview patch')
shutil.copy2(recipe / 'patches' / patch, destination)
with (source / 'debian/patches/series').open('a') as stream:
    stream.write(patch + '\n')
env = os.environ | {'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com', 'QUILT_PATCHES': 'debian/patches'}
subprocess.run(['quilt', 'push'], cwd=source, env=env, check=True)
subprocess.run(['dch', '--newversion', args.version, '--distribution', 'UNRELEASED',
                'Keep each file\'s eye correction in Gwenview configuration, restore its action state on navigation and read legacy corrections without changing the image or its attributes.'],
               cwd=source, env=env, check=True)
