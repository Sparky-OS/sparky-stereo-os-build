#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare the reviewed Wine child-surface route from the retained +6 source."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--toolkit', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    toolkit = args.toolkit.resolve()
    recipe = Path(__file__).resolve().parent
    env = os.environ | {'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
                        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
                        'QUILT_PATCHES': 'debian/patches', 'PYTHONPATH': str(toolkit)}
    old = subprocess.check_output(['dpkg-parsechangelog', '-SVersion'], cwd=source, text=True).strip()
    if old != '10.0~repack-12+stereo3d6+lc1' or (source / '.sparky-lc').exists():
        raise ValueError('Expected a fresh extraction of the retained Wine +6 descriptor')
    preserve = json.loads((source / 'debian/sparky-lean-preserve.json').read_text())
    if '*.h' not in preserve:
        raise ValueError('Missing the WIDL/WRC authored-header preserve contract')
    rules = (source / 'debian/rules').read_text()
    if '--enable-archs=x86_64,i386' not in rules:
        raise ValueError('Missing existing WoW64 configuration')
    name = 'stereo3d/0007-winex11-vulkan-child-lifecycle.patch'
    target = source / 'debian/patches' / name
    if target.exists():
        raise ValueError('Refusing to replace a patch')
    patch = recipe / 'patches/wine-vulkan-child-lifecycle.patch'
    subprocess.run(['patch', '--dry-run', '--fuzz=0', '-p1', '-i', str(patch)], cwd=source, check=True)
    subprocess.run([sys.executable, str(toolkit / 'repo/plain-from-lc.py'), '--edition-entry', str(source)], env=env, check=True)
    shutil.copy2(patch, target)
    with (source / 'debian/patches/series').open('a') as stream:
        stream.write('\n' + name + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=env, check=True)
    control = source / 'debian/control'
    text = control.read_text().replace('Build-Depends:', 'Build-Depends: libstereo-declare-dev (>= 1.8.0-1),', 1)
    anchor = 'Package: libwine\nSection: libs\nArchitecture: amd64 i386 armhf arm64\nMulti-Arch: same\nDepends:\n'
    if text.count(anchor) != 1:
        raise ValueError('Review changed libwine stanza')
    text = text.replace(anchor, anchor + ' libstereo-declare1 (>= 1.8.0-1),\n')
    control.write_text(text)
    template = source / 'debian/control.in'
    text = template.read_text()
    anchor = 'Package: libwineVERSION\nSection: libs\nArchitecture: amd64 i386 armhf arm64\nMulti-Arch: same\nDepends:\n'
    if text.count(anchor) != 1:
        raise ValueError('Review changed libwine template')
    template.write_text(text.replace(anchor, anchor + ' libstereo-declare1 (>= 1.8.0-1),\n'))
    subprocess.run(['dch', '--newversion', '10.0~repack-12+stereo3d7', '--distribution', 'unstable',
                    'Keep stereo Vulkan children attached to their actual window lifetime; maintain clipping, membership and first-paint ordering with a transactional versioned producer acknowledgement.'], cwd=source, env=env, check=True)
    command = [sys.executable, '-m', 'lean.debian_prepare', str(source), '10.0~repack-12+stereo3d7+lc1', '--toolkit', str(toolkit), '--build-dependency', 'bubblewrap']
    for pattern, reason in preserve.items():
        command += ['--preserve-source', pattern, reason]
    subprocess.run(command, env=env, check=True)
    subprocess.run([sys.executable, str(recipe / 'sync-control.py'), str(source)], env=env, check=True)


if __name__ == '__main__':
    main()
