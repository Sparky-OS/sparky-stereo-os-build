#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
trap 'chown -R "$LANE_UID:$LANE_GID" /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="nocheck parallel=${THREADS:-4}"
gpg --batch --yes --dearmor --output /archive/sparky-stereo-repo.gpg /repo/sparky-stereo-repo.asc
export DEBFULLNAME='Daniel Campos Ramos' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [signed-by=/archive/sparky-stereo-repo.gpg] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update -o APT::Update::Error-Mode=any
# next-source.sh reapplies the series with quilt; the link and start gate runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install quilt bubblewrap
# 1. the source (as the builder: the source's files are its own)
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
if [[ "${RESUME_927:-0}" == 1 ]]; then
    case "$SOURCE" in
        krdp) binary=krdp-panel-discovery; version=6.7.4-1+stereo3d12 ;;
        krdc) binary=krdc-catch; version=4:26.04.0-1+stereo3d4+lc1 ;;
        *) exit 2 ;;
    esac
    test -x "/work/lc/source/obj-x86_64-linux-gnu/bin/$binary"
    test "$(dpkg-parsechangelog -l /work/lc/source/debian/changelog -S Version)" = "$version"
    test "$(dpkg-parsechangelog -l /work/lc/source/debian/changelog -S Timestamp)" = "$SOURCE_DATE_EPOCH"
    options=(-nc)
else
    options=()
    mkdir -p /work/src /work/tmp
    chown builder:builder /work /work/src /work/tmp
    runuser -u builder -- env SOURCE="$SOURCE" TMPDIR=/work/tmp SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
        /toolkit/packages/krdp-no-picture-927/next-source.sh /base /work/src
    rm -rf /work/tmp
    mkdir -p /work/lc
    cp /base/"${SOURCE}"_*.orig.tar.* /work/src/
    cp /work/src/"${SOURCE}"_*.dsc /work/src/"${SOURCE}"_*.debian.tar.* /work/src/"${SOURCE}"_*.orig.tar.* /work/lc/
    cd /work/lc
    dpkg-source -x "${SOURCE}"_*.dsc /work/lc/source
fi
mkdir -p "$SPARKY_LC_SCRATCH"

previous=/prev
gate=()
if [[ "$SOURCE" == krdp ]]; then
    (cd /base && sha256sum --strict --check SHA256SUMS)
    (cd /pipewire-previous && sha256sum --strict --check SHA256SUMS)
    apt-get -y --no-install-recommends install \
        /pipewire/{libkpipewire-data,libkpipewire-dev,libkpipewire-dev-lc-hr,libkpipewire6,libkpipewiredmabuf6,libkpipewirerecord6,qml6-module-org-kde-pipewire}_*.deb
    # The signed publication predates both HEVC-capable KPipeWire versions.
    printf '%s\n' /pipewire/{libkpipewire-data,libkpipewire6,libkpipewiredmabuf6,libkpipewirerecord6}_*.deb > /work/siblings.txt
    printf '%s\n' /pipewire-previous/{libkpipewire-data,libkpipewire6,libkpipewiredmabuf6,libkpipewirerecord6}_6.7.4-1+stereo3d9_*.deb \
        > /work/previous-siblings.txt
    gate=(SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/work/previous-siblings.txt)
    previous=/work/previous
    mkdir -p "$previous"
    cp /base/krdp_6.7.4-1+stereo3d11_amd64.deb "$previous/"
fi
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env HOME=/work/lc SPARKY_LC_PREVIOUS_DIR="$previous" "${gate[@]}" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
	DEB_BUILD_OPTIONS="$DEB_BUILD_OPTIONS" dpkg-buildpackage -b -us -uc -j"${THREADS:-4}" "${options[@]}"
cd /work/lc
rm -rf /work/lc/source "$SPARKY_LC_SCRATCH"
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*.deb
