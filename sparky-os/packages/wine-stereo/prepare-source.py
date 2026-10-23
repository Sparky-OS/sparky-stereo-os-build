#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Prepare Wine's authored source, retained inputs and standard Lean Code hooks."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    source = args.source.resolve()
    recipe = Path(__file__).resolve().parent
    toolkit = recipe.parents[1]
    environment = os.environ | {
        'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
        'PYTHONPATH': str(toolkit),
    }
    control_path = source / 'debian/control'
    control = control_path.read_text()
    versions = {
        'unicode-data': '15.1.0-1',
        'unicode-idna': '16.0.0-1',
        'unicode-cldr-core': '46-0.1',
        'libldap2-dev': '2.6.10+dfsg-1',
        'libcapi20-dev': '1:3.27-3.2+b1',
    }
    for name, version in versions.items():
        pattern = r'(?m)^([ \t]*)' + re.escape(name) + r'(?:[ \t]*\([^)]*\))*[ \t]*,[ \t]*\n'
        matches = list(re.finditer(pattern, control))
        if not matches:
            raise ValueError(f'Review changed build dependency: {name}')
        for match in matches:
            for operator, required in re.findall(r'\((\S+)\s+([^)]*)\)', match.group(0)):
                subprocess.run(['dpkg', '--compare-versions', version, operator, required], check=True)
        first = matches[0].start()
        control = re.sub(pattern, lambda m: m[1] + name + ' (= ' + version + '),\n' if m.start() == first else '', control)
    control_path.write_text(control)
    patch_name = 'stereo3d/0005-winex11-quad-buffer-drawable-size.patch'
    destination = source / 'debian/patches' / patch_name
    if destination.exists():
        raise ValueError('Refusing to replace an existing Wine patch')
    shutil.copy2(recipe / 'patches/wine-quad-buffer-size.patch', destination)
    with (source / 'debian/patches/series').open('a') as stream:
        stream.write('\n' + patch_name + '\n')
    subprocess.run(['quilt', 'push'], cwd=source, env=environment, check=True)
    subprocess.run([
        sys.executable, '-m', 'lean.debian_prepare', str(source), args.version,
        '--toolkit', str(toolkit), '--preserve-source', '*.h',
        'WIDL and WRC also preprocess shared headers and reject filename-less line directives; preserve their exact inputs',
    ], env=environment, check=True)
    subprocess.run([
        'dch', '--append', '--maintmaint',
        'Keep quad-buffer GLX drawables at one view size while retaining the packed SBS client path; correct StereoPhoto Maker eye geometry.',
    ], cwd=source, env=environment, check=True)
    subprocess.run([sys.executable, str(recipe / 'sync-control.py'), str(source)], env=environment, check=True)
    subprocess.run([sys.executable, str(recipe / 'pin-vulkan-registry.py'), str(source)], env=environment, check=True)


if __name__ == '__main__':
    main()
