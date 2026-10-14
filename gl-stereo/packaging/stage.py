#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stage only verified upload sets, with their sources and proof logs."""
import hashlib
import os
from pathlib import Path
import shutil
import sys

build = Path(sys.argv[1])
stage = Path(sys.argv[2])
versions = ('gl-stereo_0.2.0-1', 'kscreenlocker_6.7.4-1+stereo3d1',
            'plasma-desktop_6.7.4-1+stereo3d1', 'xscreensaver_6.09+dfsg1-2+stereo3d1')

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

required = ['installed-core', 'installed-sizing', 'installed-plasma', 'package-audit',
            'installed-integrity', 'installed-benchmark']
required += ['proof-install', 'gl-stereo-build', 'kscreenlocker-build',
             'plasma-desktop-build', 'xscreensaver-build']
required += ['lintian-final-' + version for version in versions]
for name in required:
    assert (build / 'logs' / (name + '.status')).read_text().strip() == '0', name

sources = build / 'sources'
files = set()
for version in versions:
    changes = sources / (version + '_amd64.changes')
    files.add(changes)
    in_hashes = False
    for line in changes.read_text().splitlines():
        if not line.startswith(' '):
            in_hashes = line == 'Checksums-Sha256:'
        elif in_hashes:
            expected, size, name = line.split()
            assert Path(name).name == name
            path = sources / name
            assert path.stat().st_size == int(size), path
            assert digest(path) == expected, path
            files.add(path)
assert len([p for p in files if p.suffix == '.deb']) == 37
assert len([p for p in files if p.suffix == '.dsc']) == 4
stage.mkdir(parents=True, exist_ok=True)
for path in sorted(files):
    shutil.copy2(path, stage / path.name)
evidence = stage / 'evidence'
evidence.mkdir(exist_ok=True)
for name in required:
    for suffix in ('.status', '.log'):
        shutil.copy2(build / 'logs' / (name + suffix), evidence)
for name in ('build-versions.txt', 'installed-packages.txt', 'proof-install.log',
             'native-fixed-measure.log', 'installed-core-before-visual-fix.log'):
    shutil.copy2(build / 'logs' / name, evidence)
for path in sorted((build / 'installed-tests/out').glob('plasma/rig-*/*.png')):
    shutil.copy2(path, evidence / (path.parent.name + '-' + path.name))
for path in sorted((build / 'installed-tests/out').glob('**/verified.png')):
    shutil.copy2(path, evidence / ('-'.join(path.relative_to(build / 'installed-tests/out').parts)))
for path in sorted((build / 'installed-tests/out/window-sizing').glob('*/*.png')):
    shutil.copy2(path, evidence / ('sizing-' + path.parent.name + '-' + path.name))
manifest = []
for root, directories, names in os.walk(stage):
    directories[:] = sorted(name for name in directories if not name.startswith('.'))
    for name in sorted(names):
        if name.startswith('.') or name == 'SHA256SUMS':
            continue
        path = Path(root) / name
        manifest.append(f'{digest(path)}  {path.relative_to(stage)}\n')
(stage / 'SHA256SUMS').write_text(''.join(manifest))
print(f'PASS: staged {len(files)} upload files, four complete source packages and 37 debs')
