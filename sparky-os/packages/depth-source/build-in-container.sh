#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. Environment: PKG. /work is the job folder, /src the
# +lc1 source next-source.sh made, /repo the signed tree, /prev the earlier +lc1 builds, /new (dragon) the debs built
# earlier in the round, /toolkit the build tree's sparky-os.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="nocheck parallel=${THREADS:-6}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ ! -d /new ] || printf 'deb [trusted=yes] file:/new ./\n' > /etc/apt/sources.list.d/edition-new.list
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
mkdir -p /work/lc && cd /work/lc
dsc=$(ls /src/*+lc1.dsc)
cp /src/*+lc1.dsc /src/*+lc1.debian.tar.xz /src/*.orig.tar.* .
[ ! -f /src/"$(ls /src/*.orig.tar.* | head -1 | xargs basename)".asc ] || cp /src/*.orig.tar.*.asc .
dpkg-source -x "$(basename "$dsc")" /work/lc/source >/dev/null
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_PREVIOUS_SIBLINGS_FILE="${SPARKY_LC_PREVIOUS_SIBLINGS_FILE:-}" SPARKY_LC_SIBLINGS_FILE="${SPARKY_LC_SIBLINGS_FILE:-}" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
	DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" dpkg-buildpackage -us -uc -j"${THREADS:-6}"
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
