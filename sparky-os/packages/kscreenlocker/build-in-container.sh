#!/bin/bash
# Sparky Stereo OS: kscreenlocker 6.7.4-1+stereo3d2, the +stereo3d1 source package plus patches/s2-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the plain +stereo3d1 source
# package, /prev the earlier +lc1 builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s2 && cd s2
# the plain +stereo3d1 source package: sparky-os/repo/plain-from-lc.py --no-build-depends on the published +stereo3d1+lc1
# source (the same bytes each time it is made); its .dsc pins the files
echo '8f0e6c753defa20c403a0b74fc1951173cbcc4a5dcb784deabbac9b0ad3eef76  /src/kscreenlocker_6.7.4-1+stereo3d1.dsc' | sha256sum -c
cp /src/kscreenlocker_6.7.4-1+stereo3d1.dsc /src/kscreenlocker_6.7.4-1+stereo3d1.debian.tar.xz /src/kscreenlocker_6.7.4.orig.tar.xz /src/kscreenlocker_6.7.4.orig.tar.xz.asc .
dpkg-source -x kscreenlocker_6.7.4-1+stereo3d1.dsc t >/dev/null
cd t
for p in /patches/s2-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d2.txt').read_text()
assert entry.startswith('kscreenlocker (6.7.4-1+stereo3d2) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# the greeter hears from the compositor whether its screen shows depth through libstereo-declare 1.5
c = Path('debian/control')
s = c.read_text()
old = 'Build-Depends: libstereoshow-dev (>= 0.2.0),\n'
assert s.count(old) == 1 and 'libstereo-declare-dev' not in s
c.write_text(s.replace(old, old + '               libstereo-declare-dev (>= 1.5),\n'))
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s2/kscreenlocker_6.7.4-1+stereo3d2.dsc ../s2/kscreenlocker_6.7.4-1+stereo3d2.debian.tar.xz ../s2/kscreenlocker_6.7.4.orig.tar.xz ../s2/kscreenlocker_6.7.4.orig.tar.xz.asc .
dpkg-source -x kscreenlocker_6.7.4-1+stereo3d2.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.7.4-1+stereo3d2+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
dpkg-query -W libstereo-declare-dev
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
# the greeter found libstereo-declare (the layer is built in, not left out by its QUIET find_package)
mkdir -p /work/greeter-check && dpkg-deb -x /work/lc/libkscreenlocker6_6.7.4-1+stereo3d2+lc1_amd64.deb /work/greeter-check
readelf -d /work/greeter-check/usr/lib/x86_64-linux-gnu/libexec/kscreenlocker_greet | grep -F 'libstereo-declare.so'
rm -rf /work/greeter-check
