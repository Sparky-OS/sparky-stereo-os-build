#!/bin/bash
# Sparky Stereo OS: kwin 4:6.7.4-2+stereo3d31, the +stereo3d30 source package plus patches/s31-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src the +stereo3d30 source package, /prev the earlier +lc1 builds, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s31 && cd s31
# the +stereo3d30 source package as it was built and published (its .dsc pins the files)
echo '7eadc3f624fe83181ecb711a8f88f42ff11c80c886025bb1871d8fb3860a692f  /src/kwin_6.7.4-2+stereo3d30.dsc' | sha256sum -c
cp /src/kwin_6.7.4-2+stereo3d30.dsc /src/kwin_6.7.4-2+stereo3d30.debian.tar.xz /src/kwin_6.7.4.orig.tar.xz /src/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d30.dsc t >/dev/null
cd t
for p in /patches/s31-*.patch; do
    cp "$p" debian/patches/
    basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d31.txt').read_text()
assert entry.startswith('kwin (4:6.7.4-2+stereo3d31) unstable;'), entry[:60]
import email.utils
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
CHANGELOG
head -32 debian/changelog
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s31/kwin_6.7.4-2+stereo3d31.dsc ../s31/kwin_6.7.4-2+stereo3d31.debian.tar.xz ../s31/kwin_6.7.4.orig.tar.xz ../s31/kwin_6.7.4.orig.tar.xz.asc .
dpkg-source -x kwin_6.7.4-2+stereo3d31.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4:6.7.4-2+stereo3d31+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
