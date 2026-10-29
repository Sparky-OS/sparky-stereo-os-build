#!/bin/bash
# Sparky Stereo OS: libkscreen 4:6.7.4-1+stereo3d10, the +stereo3d9 source package plus patches/s10-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/29
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d9 source package,
# /extra the plasma-wayland-protocols +stereo3d10 build, /prev the earlier +lc1 builds, /patches this folder's patches.
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
echo '790218962661aaab8ec1b3c1f4032b24d5dc666d2f082b7fb92c47d6ce27141f  /src/libkscreen_6.7.4-1+stereo3d9.dsc' | sha256sum -c
cp /src/libkscreen_6.7.4-1+stereo3d9.dsc /src/libkscreen_6.7.4-1+stereo3d9.debian.tar.xz /src/libkscreen_6.7.4.orig.tar.xz /src/libkscreen_6.7.4.orig.tar.xz.asc .
dpkg-source -x libkscreen_6.7.4-1+stereo3d9.dsc t >/dev/null
cd t
for p in /patches/s10-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d10.txt').read_text()
assert entry.startswith('libkscreen (4:6.7.4-1+stereo3d10) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# version 30 of the output device protocol: its minimum, and the build stops on a protocol without the new flag
c = Path('debian/control'); s = c.read_text()
old = 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d9~)'
assert s.count(old) == 1, old
c.write_text(s.replace(old, 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d10~)'))
r = Path('debian/rules'); s = r.read_text()
old = '\tgrep -q stereo_swap_eyes /usr/share/plasma-wayland-protocols/kde-output-device-v2.xml\n'
assert s.count(old) == 1, old
r.write_text(s.replace(old, old + '\tgrep -q stereo_sequential_displayport /usr/share/plasma-wayland-protocols/kde-output-device-v2.xml\n'))
CHANGELOG
head -24 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s10/libkscreen_6.7.4-1+stereo3d10.dsc ../s10/libkscreen_6.7.4-1+stereo3d10.debian.tar.xz ../s10/libkscreen_6.7.4.orig.tar.xz ../s10/libkscreen_6.7.4.orig.tar.xz.asc .
dpkg-source -x libkscreen_6.7.4-1+stereo3d10.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-1+stereo3d10+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
echo "== installing this round's builds first"
apt-get -y --no-install-recommends install /extra/*.deb > /work/extra-install.log 2>&1 || { tail -20 /work/extra-install.log; exit 1; }
dpkg-query -W plasma-wayland-protocols
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
