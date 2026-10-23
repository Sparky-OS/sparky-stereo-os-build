#!/bin/bash
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
# No GPU or desktop is exposed while preparing the installed qualification image.
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export DEBIAN_FRONTEND=noninteractive
trap 'chown -R 1000:1000 /w' EXIT
python3 - <<'APT_SOURCES'
from pathlib import Path
archive=Path('/var/tmp/order223-original-apt-sources')
archive.mkdir(exist_ok=True)
for directory in (Path('/etc/apt/sources.list.d'),):
 for path in directory.iterdir():
  if path.suffix in ('.list','.sources'):
   path.rename(archive/path.name)
Path('/etc/apt/sources.list').write_text('')
APT_SOURCES
printf 'deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian.list
printf 'deb [signed-by=/pub/sparky-stereo-repo.asc] file:/pub mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb [signed-by=/sparky-repo.asc] https://repo.sparkylinux.org/ core main\ndeb [signed-by=/sparky-repo.asc] https://repo.sparkylinux.org/ tiamat main\n' > /etc/apt/sources.list.d/sparky.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
if [ "$PHASE" = after ]; then
 printf 'deb [trusted=yes] file:/new ./\n' > /etc/apt/sources.list.d/edition-new.list
fi
apt-get -y update > /w/apt-update.log 2>&1
packages=(ffmpeg mpv libmpv-dev libmlt-dev libmlt++-dev libmlt-data melt qt6-multimedia-dev qml6-module-qtmultimedia kdenlive vlc-stereo libvlc-dev sparky-stereo-hardware pkgconf gcc g++ weston vulkan-tools vainfo)
if [ "$PHASE" = after ]; then
 packages+=(libmedia-gpu-route-dev media-gpu-route-tools libplacebo-dev)
else
 packages+=(libplacebo-dev=2:7.360.1-dmo1 libplacebo360=2:7.360.1-dmo1)
fi
mapfile -t cohort < <(python3 - <<'COHORT'
import os,re
from pathlib import Path
phase=os.environ['PHASE']
inputs=[Path('/new/Packages')] if phase=='after' else [Path('/pub/dists/mashtabba/main/binary-'+arch+'/Packages') for arch in ('amd64','all')]
sources={'ffmpeg-dmo','mpv-dmo','mlt','qt6-multimedia','kdenlive','vlc','sparky-stereo-hardware','media-gpu-route','libplacebo-dmo'}
for path in inputs:
 for stanza in path.read_text().split('\n\n'):
  d=dict(l.split(': ',1) for l in stanza.splitlines() if ': ' in l and not l.startswith(' '))
  name=d.get('Package','')
  if d.get('Source',name).split(' ')[0] not in sources or d.get('Architecture') not in ('amd64','all'):continue
  if name.endswith(('-dbgsym','-lc-hr','-examples')) or re.search(r'-doc(?:-html|-dev)?$',name):continue
  print(name+'='+d['Version'])
COHORT
)
apt-get -y --no-install-recommends install "${packages[@]}" "${cohort[@]}" > /w/apt-install.log 2>&1
mkdir -p /w/logs /w/final
sh /kit/packaging/build-installed-probes.sh > /w/probes-build.log 2>&1
dpkg-query -W -f='${binary:Package}\t${Version}\n' ffmpeg libavcodec63 libavcodec-dev mpv libmpv2 libmpv-dev libplacebo360 libmlt7 libmlt-dev libqt6multimedia6 kdenlive vlc-stereo sparky-stereo-hardware > /w/installed-versions.tsv
if [ "$PHASE" = after ]; then
 dpkg-query -W -f='${binary:Package}\t${Version}\n' libmedia-gpu-route0 >> /w/installed-versions.tsv
fi
