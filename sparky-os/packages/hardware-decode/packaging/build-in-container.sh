#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# /work is owned scratch, /pub the signed predecessor repository, /new the earlier
# staged cohort, /previous the published binary controls, /kit the build tree's
# packages directory, /toolkit the existing release machinery.
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/new ./\n' > /etc/apt/sources.list.d/edition-new.list
printf 'deb [signed-by=/pub/sparky-stereo-repo.asc] file:/pub mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends install quilt devscripts dpkg-dev > /work/prepare-deps.log 2>&1
python3 /kit/hardware-decode/packaging/build-source.py "$PKG" /work /pub /toolkit --libplacebo-source /libplacebo-input > /work/prepare.log 2>&1
apt-get -y --no-install-recommends build-dep /work/source > /work/build-dep.log 2>&1
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/previous dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*.deb > /work/check-debs.log 2>&1
PYTHONPATH=/toolkit python3 -m lean.release check-link --previous-dir /previous /work/*.deb > /work/check-link.log 2>&1
