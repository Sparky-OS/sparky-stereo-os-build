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
p.add_argument('--published-lc', action='store_true',
               help="retain the published source package's existing Lean Code integration")
p.add_argument('--libplacebo-min-version', help='libplacebo release retaining compositor device order')
p.add_argument('--ffmpeg-min-version', help='FFmpeg release containing the format-query cleanup')
p.add_argument('--gpu-route-min-version', help='shared GPU routing library release')
p.add_argument('--mlt-min-version', help='MLT release containing automatic precision-preserving decoding')
p.add_argument('--entry', type=Path, help='changelog entry text for this release, instead of the routing entry')
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
integrated = (source/'debian/sparky-lean-toolkit/lean/source_tree.py').is_file()
if a.published_lc:
    if not integrated or not current.endswith('+lc1') or not a.version.endswith('+lc1'):
        p.error('--published-lc requires an integrated published lc1 source and lc1 successor')
    if 'sparky-lean-toolkit' not in (source/'debian/rules').read_text():
        p.error('published source lacks its retained Lean Code build hooks')
elif '+lc' in a.version or '+lc' in current or integrated:
    p.error('prepare plain sources or explicitly retain --published-lc integration')
patches = source/'debian/patches'
series = patches/'series'
existing = series.read_text() if series.exists() else ''
# Retain the accepted full SBS corrections when starting with published plain sources.
inputs = []
if a.package in ['mpv-dmo', 'mlt', 'kdenlive', 'qt6-multimedia']:
    inputs.extend(sorted((here.parent/'full-sbs/patches'/a.package).glob('*.patch')))
inputs.extend(sorted((here/'patches'/a.package).glob('*.patch')))
# Patches an earlier release carried and this one leaves out, one name a line, each with its reason in DROPPED.
dropped_list = here/'patches'/a.package/'DROPPED'
dropped = [line.split()[0] for line in dropped_list.read_text().splitlines()
           if line.strip() and not line.startswith('#')] if dropped_list.exists() else []
assert inputs or dropped
patches.mkdir(exist_ok=True)
if dropped:
    quilt_env = os.environ | {'QUILT_PATCHES': 'debian/patches'}
    subprocess.run(['quilt', 'pop', '-a'], cwd=source, env=quilt_env, check=True)
    names = [name for name in existing.splitlines() if name.strip()]
    for name in dropped:
        if name not in names:
            raise SystemExit(f'Dropped patch is not in the series: {name}')
        names.remove(name)
        (patches/name).unlink()
    series.write_text(''.join(name + '\n' for name in names))
    existing = series.read_text()
    shutil.rmtree(source/'.pc', ignore_errors=True)
    if names:
        subprocess.run(['quilt', 'push', '-a'], cwd=source, env=quilt_env, check=True)
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
if inputs:
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
            # An explicit floor supplements shlibs; a floor an earlier release
            # wrote is raised in place.
            sections[i], changed = re.subn(r'(^Depends:(?:[^\n]|\n[ \t])*?)\b' + re.escape(package) + r' \(>= [^)]*\)',
                lambda m: f'{m.group(1)}{package} (>= {version})', section, count=1, flags=re.M)
            if not changed:
                sections[i], changed = re.subn(r'^Depends: ',
                    f'Depends: {package} (>= {version}), ', section, count=1, flags=re.M)
            assert changed == 1
            found = True
    assert found, binary
    text = '\n\n'.join(sections)
def build_dependency(package, version):
    global text
    text, changed = re.subn(r'(^Build-Depends:(?:[^\n]|\n[ \t])*?)\b' + re.escape(package) + r' \(>= [^)]*\)',
        lambda m: f'{m.group(1)}{package} (>= {version})', text, count=1, flags=re.M)
    if not changed:
        text, changed = re.subn(r'^Build-Depends:[ \t]*',
            f'Build-Depends: {package} (>= {version}), ', text, count=1, flags=re.M)
    assert changed == 1
if a.package in ['mlt', 'vlc', 'qt6-multimedia']:
    binary = {'mlt': 'libmlt7', 'vlc': 'vlc-stereo', 'qt6-multimedia': 'libqt6multimedia6'}[a.package]
    dependency(binary, 'libavcodec63', a.ffmpeg_min_version)
    dependency(binary, 'libmedia-gpu-route0', a.gpu_route_min_version)
    build_dependency('libmedia-gpu-route-dev', a.gpu_route_min_version)
if a.package == 'mpv-dmo' and a.libplacebo_min_version:
    dependency('mpv', 'libplacebo360', a.libplacebo_min_version)
    dependency('libmpv2', 'libplacebo360', a.libplacebo_min_version)
    build_dependency('libplacebo-dev', a.libplacebo_min_version)
if a.package == 'mpv-dmo' and a.gpu_route_min_version:
    # The copy-back choice of the automatic hardware decoding modes.
    dependency('mpv', 'libmedia-gpu-route0', a.gpu_route_min_version)
    dependency('libmpv2', 'libmedia-gpu-route0', a.gpu_route_min_version)
    build_dependency('libmedia-gpu-route-dev', a.gpu_route_min_version)
    rules = source/'debian/rules'
    rules_text = rules.read_text()
    if '-Dmedia-gpu-route=enabled' not in rules_text:
        rules_text, changed = re.subn(r'^(\t-Dstereo-dibr=enabled \\\n)', r'\1\t-Dmedia-gpu-route=enabled \\\n',
                                      rules_text, count=1, flags=re.M)
        assert changed == 1
        rules.write_text(rules_text)
if a.package == 'kdenlive':
    dependency('kdenlive', 'libmlt7', a.mlt_min_version)
control.write_text(text)
body = (a.entry.read_text().rstrip('\n') + '\n' if a.entry else
        '  * Follow the display GPU for media where its decoder preserves source\n'
        '    precision and retain software fallback and stereo frame properties.\n')
entry = (f'{a.package} ({a.version}) unstable; urgency=medium\n\n' + body + '\n'
         ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
         + email.utils.formatdate(localtime=True) + '\n\n')
changelog.write_text(entry + old)
print(f'Prepared {a.package} {a.version}; existing Lean Code integration retained: {a.published_lc}.')
