#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Append the TMPDIR ownership fix to an already prepared Wine source."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    source = args.source.resolve()
    recipe = Path(__file__).resolve().parent
    environment = os.environ | {
        'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
        'QUILT_PATCHES': 'debian/patches',
    }
    old = subprocess.check_output(['dpkg-parsechangelog', '-S', 'Version'], cwd=source, text=True).strip()
    subprocess.run(['dpkg', '--compare-versions', args.version, 'gt', old], check=True)
    patch_name = 'fixes/temporary-directory-ownership.patch'
    destination = source / 'debian/patches' / patch_name
    if destination.exists():
        raise ValueError('Refusing to replace an existing Wine patch')
    series = source / 'debian/patches/series'
    if patch_name in series.read_text():
        raise ValueError('Fix is already in the patch series')
    for retained in ('debian/sparky-lean-preserve.json', 'debian/vulkan-registry/provenance.json',
                     'debian/patches/stereo3d/0005-winex11-quad-buffer-drawable-size.patch',
                     'debian/patches/stereo3d/0006-winex11-popup-metadata.patch'):
        if not (source / retained).is_file():
            raise ValueError('Expected prepared Wine input: ' + retained)
    rules = (source / 'debian/rules').read_text()
    if 'sparky-lean-toolkit' not in rules or '--enable-archs=x86_64,i386' not in rules:
        raise ValueError('Expected existing LC and WoW64 integration')
    patch = recipe / 'patches/wine-tmpdir-ownership.patch'
    subprocess.run(['patch', '--dry-run', '-p1', '-i', str(patch)], cwd=source, check=True)
    shutil.copy2(patch, destination)
    with series.open('a') as stream:
        stream.write('\n' + patch_name + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=environment, check=True)
    subprocess.run(['dch', '--newversion', args.version, '--distribution', 'UNRELEASED',
                    'Fix the wineserver temporary-directory helper freeing borrowed TMPDIR memory; retain native win32 compatibility and all stereo patches.'],
                   cwd=source, env=environment, check=True)
    subprocess.run(['sh', 'debian/scripts/check-control'], cwd=source, env=environment, check=True)


if __name__ == '__main__':
    main()
