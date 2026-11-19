#!/bin/bash
# Sparky Stereo OS: plasma-gamemode 0.0~git20240315.4d60358-2+stereo3d1, Debian's 0.0~git20240315.4d60358-2 with the GamesModel fix, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor build for the link gate, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 0.0~git20240315.4d60358-2 source package (the .dsc pins the files)
echo '41c88941568d532c484201eccd54ceb8bd2f8ed033816a9a98183c0cf1587f9d  /src/plasma-gamemode_0.0~git20240315.4d60358-2.dsc' | sha256sum -c
cp /src/plasma-gamemode_0.0~git20240315.4d60358-2.dsc /src/plasma-gamemode_0.0~git20240315.4d60358-2.debian.tar.xz /src/plasma-gamemode_0.0~git20240315.4d60358.orig.tar.xz .
dpkg-source -x plasma-gamemode_0.0~git20240315.4d60358-2.dsc t >/dev/null
cd t
# Debian's source has no patch series yet
mkdir -p debian/patches
for p in /patches/0001-gamesmodel-each-answer-owns-its-watcher.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('plasma-gamemode (0.0~git20240315.4d60358-2+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('plasma-gamemode (0.0~git20240315.4d60358-2) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -16 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/plasma-gamemode_0.0~git20240315.4d60358-2+stereo3d1.dsc ../s1/plasma-gamemode_0.0~git20240315.4d60358-2+stereo3d1.debian.tar.xz ../s1/plasma-gamemode_0.0~git20240315.4d60358.orig.tar.xz .
dpkg-source -x plasma-gamemode_0.0~git20240315.4d60358-2+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 0.0~git20240315.4d60358-2+stereo3d1+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' qt6-base-dev libplasma-dev extra-cmake-modules >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
