#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
trap 'chown -R "$LANE_UID:$LANE_GID" /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="nocheck parallel=${THREADS:-4}"
gpg --batch --dearmor --output /archive/sparky-stereo-repo.gpg /repo/sparky-stereo-repo.asc
export DEBFULLNAME='Daniel Campos Ramos' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [signed-by=/archive/sparky-stereo-repo.gpg] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update -o APT::Update::Error-Mode=any
# next-source.sh reapplies the series with quilt; the link and start gate runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install quilt bubblewrap
# 1. the source (as the builder: the source's files are its own)
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/src /work/tmp && chown builder:builder /work /work/src /work/tmp
runuser -u builder -- env SOURCE="$SOURCE" TMPDIR=/work/tmp SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" /toolkit/packages/krdp-no-picture-927/next-source.sh /base /work/src
rm -rf /work/tmp
mkdir -p /work/lc "$SPARKY_LC_SCRATCH"
cp /base/"${SOURCE}"_*.orig.tar.* /work/src/
cp /work/src/"${SOURCE}"_*.dsc /work/src/"${SOURCE}"_*.debian.tar.* /work/src/"${SOURCE}"_*.orig.tar.* /work/lc/
cd /work/lc
dpkg-source -x "${SOURCE}"_*.dsc /work/lc/source
if [[ "$SOURCE" == krdp ]]; then
    apt-get -y --no-install-recommends install /pipewire/{libkpipewire-data,libkpipewire-dev,libkpipewire6,libkpipewiredmabuf6,libkpipewirerecord6}_*.deb
fi
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env HOME=/work/lc SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
	DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" dpkg-buildpackage -b -us -uc -j"${THREADS:-4}"
cd /work/lc
rm -rf /work/lc/source "$SPARKY_LC_SCRATCH"
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*.deb
