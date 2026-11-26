#!/bin/bash
# Sparky Stereo OS: kvantum 1.1.8-1+stereo3d1, Debian's 1.1.8-1 with the scroll-arrows-together patch, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor builds for the link gate, /tools this recipe folder, /toolkit the build tree's sparky-os.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 1.1.8-1 source package (the .dsc pins the files; build.sh checked them against source.sha256)
cp /src/kvantum_1.1.8-1.dsc /src/kvantum_1.1.8-1.debian.tar.xz /src/kvantum_1.1.8.orig.tar.xz /src/kvantum_1.1.8.orig.tar.xz.asc .
dpkg-source -x kvantum_1.1.8-1.dsc t >/dev/null
cd t
mkdir -p debian/patches
for p in /tools/patches/scroll-arrows-together.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
# only our own patch is credited to us in debian/copyright (skill edition-packaging, crediting our additions)
python3 /toolkit/repo/provenance-files.py . 'scroll-arrows-together.patch'
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('kvantum (1.1.8-1+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('kvantum (1.1.8-1) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -12 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/kvantum_1.1.8-1+stereo3d1.dsc ../s1/kvantum_1.1.8-1+stereo3d1.debian.tar.xz ../s1/kvantum_1.1.8.orig.tar.xz ../s1/kvantum_1.1.8.orig.tar.xz.asc .
dpkg-source -x kvantum_1.1.8-1+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 1.1.8-1+stereo3d1+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y dist-upgrade >/work/dist-upgrade.log 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' qt6-base-dev libqt5svg5-dev qt6-svg-dev libkf6windowsystem-dev cmake g++ >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -sa -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
rm -rf /work/lc/source
