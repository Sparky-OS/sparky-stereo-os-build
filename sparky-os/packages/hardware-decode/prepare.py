#!/usr/bin/env python3
"""Prepare plain Debian sources; the existing Lean Code release pipeline follows."""
import argparse
import email.utils
import os
from pathlib import Path
import re
import shutil
import subprocess

here = Path(__file__).resolve().parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('package', choices=['ffmpeg-dmo', 'mpv-dmo', 'mlt', 'kdenlive', 'vlc', 'qt6-multimedia', 'libplacebo-dmo'])
p.add_argument('source', type=Path)
p.add_argument('--version', required=True)
p.add_argument('--ffmpeg-min-version', help='FFmpeg release containing the format-query cleanup')
p.add_argument('--gpu-route-min-version', help='shared GPU routing library release')
p.add_argument('--mlt-min-version', help='MLT release containing automatic precision-preserving decoding')
a = p.parse_args()
source = a.source.resolve()
if a.package in ['mlt', 'vlc', 'qt6-multimedia'] and not a.ffmpeg_min_version:
    p.error('--ffmpeg-min-version is required for the safe software fallback dependency')
if a.package in ['mlt', 'vlc', 'qt6-multimedia'] and not a.gpu_route_min_version:
    p.error('--gpu-route-min-version is required for the shared default GPU policy')
if a.package == 'kdenlive' and not a.mlt_min_version:
    p.error('--mlt-min-version is required for automatic decoding')
changelog = source/'debian/changelog'
old = changelog.read_text()
if not old.startswith(a.package + ' ('):
    p.error('source package does not match')
current = old.split('(', 1)[1].split(')', 1)[0]
subprocess.run(['dpkg', '--compare-versions', a.version, 'gt', current], check=True)
if '+lc' in a.version or '+lc' in current:
    p.error('prepare plain sources before the existing Lean Code pipeline')
patches = source/'debian/patches'
series = patches/'series'
existing = series.read_text() if series.exists() else ''
# Retain the accepted full SBS corrections when starting with published plain sources.
inputs = []
if a.package in ['mpv-dmo', 'mlt', 'kdenlive', 'qt6-multimedia']:
    inputs.extend(sorted((here.parent/'full-sbs/patches'/a.package).glob('*.patch')))
inputs.extend(sorted((here/'patches'/a.package).glob('*.patch')))
assert inputs
patches.mkdir(exist_ok=True)
for patch in inputs:
    if patch.name in existing.splitlines():
        continue
    destination = patches/patch.name
    if destination.exists():
        raise SystemExit(f'Unregistered patch already exists: {destination}')
    shutil.copyfile(patch, destination)
    with series.open('a') as f:
        f.write(patch.name + '\n')
# dpkg-source has already applied the package's original series.
subprocess.run(['quilt', 'push', '-a'], cwd=source,
               env=os.environ | {'QUILT_PATCHES': 'debian/patches'}, check=True)
control = source/'debian/control'
text = control.read_text()
def dependency(binary, package, version):
    global text
    sections = text.split('\n\n')
    found = False
    for i, section in enumerate(sections):
        if section.startswith('Package: ' + binary + '\n'):
            # An explicit floor supplements shlibs and any older existing floor.
            sections[i], changed = re.subn(r'^Depends: ',
                f'Depends: {package} (>= {version}), ', section, count=1, flags=re.M)
            assert changed == 1
            found = True
    assert found, binary
    text = '\n\n'.join(sections)
if a.package in ['mlt', 'vlc', 'qt6-multimedia']:
    binary = {'mlt': 'libmlt7', 'vlc': 'vlc-stereo', 'qt6-multimedia': 'libqt6multimedia6'}[a.package]
    dependency(binary, 'libavcodec63', a.ffmpeg_min_version)
    dependency(binary, 'libmedia-gpu-route0', a.gpu_route_min_version)
    text, changed = re.subn(r'^Build-Depends:[ \t]*',
        f'Build-Depends: libmedia-gpu-route-dev (>= {a.gpu_route_min_version}), ',
        text, count=1, flags=re.M)
    assert changed == 1
if a.package == 'kdenlive':
    dependency('kdenlive', 'libmlt7', a.mlt_min_version)
control.write_text(text)
entry = (f'{a.package} ({a.version}) unstable; urgency=medium\n\n'
         '  * Follow the display GPU for media where its decoder preserves source\n'
         '    precision and retain software fallback and stereo frame properties.\n\n'
         ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
         + email.utils.formatdate(localtime=True) + '\n\n')
changelog.write_text(entry + old)
print(f'Prepared plain {a.package} {a.version}; run the existing qualified release pipeline.')
