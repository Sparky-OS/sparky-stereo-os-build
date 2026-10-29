#!/bin/bash
# Sparky Stereo OS: plasma-wayland-protocols 1.21.0-1+stereo3d10, the +stereo3d9 source package plus patches/s10-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23, +stereo3d10 2026/10/29
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d9 source package, /prev the earlier +lc1 builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s10 && cd s10
# the plain +stereo3d9 source package as it was built (ORDER 238); its .dsc pins the files, and plain-from-lc.py gives the
# same tree from the published +lc1 source
echo 'ee1b1c1cc508584f83f9e1d43898bb3c7a2411136685f82d9471fd82dda65169  /src/plasma-wayland-protocols_1.21.0-1+stereo3d9.dsc' | sha256sum -c
cp /src/plasma-wayland-protocols_1.21.0-1+stereo3d9.dsc /src/plasma-wayland-protocols_1.21.0-1+stereo3d9.debian.tar.xz /src/plasma-wayland-protocols_1.21.0.orig.tar.xz /src/plasma-wayland-protocols_1.21.0.orig.tar.xz.asc .
dpkg-source -x plasma-wayland-protocols_1.21.0-1+stereo3d9.dsc t >/dev/null
cd t
for p in /patches/s10-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d10.txt').read_text()
assert entry.startswith('plasma-wayland-protocols (1.21.0-1+stereo3d10) unstable;'), entry[:60]
import email.utils
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -24 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s10/plasma-wayland-protocols_1.21.0-1+stereo3d10.dsc ../s10/plasma-wayland-protocols_1.21.0-1+stereo3d10.debian.tar.xz ../s10/plasma-wayland-protocols_1.21.0.orig.tar.xz ../s10/plasma-wayland-protocols_1.21.0.orig.tar.xz.asc .
dpkg-source -x plasma-wayland-protocols_1.21.0-1+stereo3d10.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 1.21.0-1+stereo3d10+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
