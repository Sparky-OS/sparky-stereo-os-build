#!/bin/bash
# Sparky Stereo OS: qt6-declarative 6.11.2+dfsg-3+stereo3d1, Debian's 6.11.2+dfsg-3 plus patches/s1-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package, /prev earlier builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's source package as testing's Sources index lists it (2026-10-23)
echo '551e8ac8fa20e4591d084e897e210dbe69a77bd45b6863c388fbb58ca6de7b76  /src/qt6-declarative_6.11.2+dfsg-3.dsc' | sha256sum -c
cp /src/qt6-declarative_6.11.2+dfsg-3.dsc /src/qt6-declarative_6.11.2+dfsg-3.debian.tar.xz /src/qt6-declarative_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-declarative_6.11.2+dfsg-3.dsc t >/dev/null
cd t
for p in /patches/s1-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils, re
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('qt6-declarative (6.11.2+dfsg-3+stereo3d1) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -24 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/qt6-declarative_6.11.2+dfsg-3+stereo3d1.dsc ../s1/qt6-declarative_6.11.2+dfsg-3+stereo3d1.debian.tar.xz ../s1/qt6-declarative_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-declarative_6.11.2+dfsg-3+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
# The source-consumer plan of qt6-base and qt6-multimedia (sparky-os/release/run-native-batch.py): syncqt reads the
# private headers' warning comments, and Qt's test corpus holds comment and syntax fixtures read as text.
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.11.2+dfsg-3+stereo3d1+lc1 --toolkit /toolkit \
	--preserve-source 'src/*_p.h' 'Qt syncqt reads the private-API warning comments, including We mean it.; retain its input headers exactly' \
	--preserve-source 'tests/*' 'Qt test inputs include deliberate comment and invalid-syntax fixtures consumed as text by qmllint, qmlformat and the QML compiler tests; preserve the upstream test corpus while projecting production source'
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
