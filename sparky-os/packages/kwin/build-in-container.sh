#!/bin/bash
# Sparky Stereo OS: kwin 4:6.7.4-2+stereo3d36, the +stereo3d35 source package plus patches/s36-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, +stereo3d36 2026/10/29
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d35 source package,
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
mkdir s36 && cd s36
# the plain +stereo3d35 source package, made from the published kwin_6.7.4-2+stereo3d35+lc1.dsc by plain-from-lc.py (the same
# tree as the plain +stereo3d34 source plus s35-0001 to s35-0012 and the published entry); its .dsc pins the files
echo 'b448b54c105c61ee7c6ecf8c8a66dbbbf56203ed92407b8d7462a2a5f490f8c8  /src/kwin_6.7.4-2+stereo3d35.dsc' | sha256sum -c
cp /src/kwin_6.7.4-2+stereo3d35.dsc /src/kwin_6.7.4-2+stereo3d35.debian.tar.xz /src/kwin_6.7.4.orig.tar.xz /src/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d35.dsc t >/dev/null
cd t
for p in /patches/s36-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d36.txt').read_text()
assert entry.startswith('kwin (4:6.7.4-2+stereo3d36) unstable;'), entry[:60]
import email.utils
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# version 30 of the output device protocol: its minimum, and the build stops on a protocol without DisplayPort's flag
# (KWin would take its in-tree copy, version 29, and never announce the mode)
c = Path('debian/control'); s = c.read_text()
old = 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d7~)'
assert s.count(old) == 1, old
c.write_text(s.replace(old, 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d10~)'))
r = Path('debian/rules'); s = r.read_text()
old = 'override_dh_auto_configure:\n'
assert s.count(old) == 1, old
r.write_text(s.replace(old, old + '\tgrep -q stereo_sequential_displayport /usr/share/plasma-wayland-protocols/kde-output-device-v2.xml\n'))
CHANGELOG
head -40 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s36/kwin_6.7.4-2+stereo3d36.dsc ../s36/kwin_6.7.4-2+stereo3d36.debian.tar.xz ../s36/kwin_6.7.4.orig.tar.xz ../s36/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d36.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d36+lc1 --toolkit /toolkit
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
