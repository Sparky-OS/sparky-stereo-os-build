#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Export the clean Sparky HandBrake commit and deb-multimedia packaging."""
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile

fork, packaging, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
assert not subprocess.check_output(['git', 'status', '--porcelain'], cwd=fork), 'Commit the fork first'
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=fork, text=True).strip()
stamp = int(subprocess.check_output(['git', 'show', '-s', '--format=%ct', 'HEAD'], cwd=fork))
upstream = '1.11.2+git' + commit[:9]
dirname = 'handbrake-dmo-' + upstream
output.mkdir(parents=True, exist_ok=True)
source = output / dirname
assert not source.exists(), source
archive = output / ('handbrake-dmo_' + upstream + '.orig.tar.xz')
raw = subprocess.check_output(['git', 'archive', '--format=tar', '--prefix=' + dirname + '/', 'HEAD'], cwd=fork)
info = subprocess.check_output(['sh', 'scripts/repo-info.sh', str(fork)], cwd=fork)
with tarfile.open(fileobj=io.BytesIO(raw)) as original, tarfile.open(archive, 'w:xz') as final:
    for member in original:
        final.addfile(member, original.extractfile(member) if member.isfile() else None)
    member = tarfile.TarInfo(dirname + '/version.txt')
    member.size = len(info); member.mtime = stamp; member.mode = 0o644
    final.addfile(member, io.BytesIO(info))
with tarfile.open(archive) as tar:
    tar.extractall(output, filter='data')
with tarfile.open(packaging) as tar:
    tar.extractall(source, filter='data')
patches = source / 'debian/patches'
for patch in patches.iterdir():
    patch.unlink()
(patches / 'series').write_text('')
(source / 'debian/sparky-fork-source.json').write_text(json.dumps({
    'repository': 'https://github.com/Sparky-OS/HandBrake.git', 'commit': commit,
    'baseline': '1.11.2', 'upstream_version': upstream,
    'packaging_baseline': 'handbrake-dmo 1:1.11.2-dmo3',
}, indent=2) + '\n')
print(source)
