#!/bin/bash
# Sparky Stereo OS: stereo-declare 1.6.0-1 from the release commit of libstereo-declare, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, 1.5.0 on 2026/10/23, 1.6.0 on 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /fork the release clone,
# /prev the earlier +lc1 builds. The release commit carries debian/ with its changelog entry; the tests run in the build.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
NEWV=1.6.0-1
REV=1e98122f4399ed0a9647def2407855744288c95e
PREFIX=stereo-declare-1.6.0
ORIG=stereo-declare_1.6.0.orig.tar.xz
git config --global safe.directory '*'
test "$(git -C /fork show "$REV":debian/changelog | head -1)" = "stereo-declare ($NEWV) unstable; urgency=medium"
mkdir -p /work/plain /work/export && cd /work/plain
git -C /fork archive --format=tar --prefix="$PREFIX/" "$REV" | tar -x -C /work/export
cp -a "/work/export/$PREFIX/debian" /work/debian-export
rm -rf "/work/export/$PREFIX/debian"
stamp=$(git -C /fork log -1 --format=%ct "$REV")
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C /work/export -cf - "$PREFIX" | xz -9e > "$ORIG"
tar -xf "$ORIG"
cp -a /work/debian-export "$PREFIX/debian"
dpkg-source -b "$PREFIX" >/dev/null
rm -rf "$PREFIX"
ls
mkdir -p /work/lc && cd /work/lc
cp /work/plain/* .
dpkg-source -x "stereo-declare_$NEWV.dsc" /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
