#!/bin/bash
# Sparky Stereo OS: qt6-base 6.11.2+dfsg-5+stereo3d13, the +stereo3d12 source package plus patches/s13-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23, +stereo3d13 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the plain +stereo3d12 source
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
mkdir s13 && cd s13
# the plain +stereo3d12 source package: sparky-os/repo/plain-from-lc.py on the published +stereo3d12+lc1 source (the same
# bytes each time it is made); its .dsc pins the files
echo 'ac2e9554baf0ffd9abb610d6323d6fb3020705657daf0e93c3e4723df80f23a3  /src/qt6-base_6.11.2+dfsg-5+stereo3d12.dsc' | sha256sum -c
cp /src/qt6-base_6.11.2+dfsg-5+stereo3d12.dsc /src/qt6-base_6.11.2+dfsg-5+stereo3d12.debian.tar.xz /src/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d12.dsc t >/dev/null
cd t
for p in /patches/s13-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import email.utils
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d13.txt').read_text()
assert entry.startswith('qt6-base (6.11.2+dfsg-5+stereo3d13) unstable;'), entry[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
# the +stereo3d12 source already installs kde-stereo-content-v1.xml (s8-0001)
assert 'kde-stereo-content-v1.xml' in Path('debian/qt6-base-dev.install').read_text()
CHANGELOG
head -30 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s13/qt6-base_6.11.2+dfsg-5+stereo3d13.dsc ../s13/qt6-base_6.11.2+dfsg-5+stereo3d13.debian.tar.xz ../s13/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d13.dsc /work/lc/source >/dev/null
cd /work/lc/source
# The same source-consumer plan as the published +stereo3d12+lc1 (sparky-os/release/run-native-batch.py).
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.11.2+dfsg-5+stereo3d13+lc1 --toolkit /toolkit \
	--preserve-source 'src/*_p.h' 'Qt syncqt reads the private-API warning comments, including We mean it.; retain its input headers exactly' \
	--preserve-source 'tests/*' 'Qt test inputs include deliberate comment/splice and invalid-syntax fixtures consumed as text by qmake and moc; preserve the upstream test corpus while projecting production source' \
	--preserve-source 'src/corelib/global/qoperatingsystemversion.h' 'Qt syncqt generates a different public-header set after textual projection; retain this input exactly, verified by the authored/projected syncqt comparison'
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
