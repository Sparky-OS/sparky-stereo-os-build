#!/bin/bash
# Sparky Stereo OS: OpenRGB 1.0 from the project's release tag, in a throwaway sparky-pkg-base:amd64 container.
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# The orig tarball is git archive of tag release_1.0 minus the paths of Files-Excluded in debian/copyright.
# Usage: build.sh [workdir]   (default /K3D/temp/partners/queue/hand-installed-apps/orgb/build; 4 threads)
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
WORK=${1:-/K3D/temp/partners/queue/hand-installed-apps/orgb/build}
mkdir -p "$WORK"
docker run --rm -e HOST_UID=$(id -u) -v "$WORK":/out -v "$HERE/debian":/debian-ours:ro sparky-pkg-base:amd64 bash -c '
set -e
sed -i "s/^Suites: unstable/Suites: testing testing-updates/" /etc/apt/sources.list.d/debian.sources
export DEBIAN_FRONTEND=noninteractive LC_ALL=C DEB_BUILD_OPTIONS="parallel=4"
apt-get update -qq >/dev/null; apt-get install -y -qq ca-certificates git dpkg-dev build-essential fakeroot lintian xz-utils >/dev/null
cd /out && rm -rf work && mkdir work && cd work
git clone -q --depth 1 --branch release_1.0 https://gitlab.com/CalcProgrammer1/OpenRGB.git up
echo "tag commit: $(git -C up rev-parse HEAD)"
mkdir openrgb-1.0+ds
git -C up archive --format=tar HEAD | tar xf - -C openrgb-1.0+ds
cd openrgb-1.0+ds
rm -rf debian dependencies/hidapi-hotplug-win dependencies/hidapi-win dependencies/libusb-1.0.27 dependencies/mbedtls-3.2.1 dependencies/PawnIO
cd ..
tar --sort=name --mtime=@1789000000 --owner=0 --group=0 -cJf openrgb_1.0+ds.orig.tar.xz openrgb-1.0+ds
cp -a /debian-ours openrgb-1.0+ds/debian
cd openrgb-1.0+ds
apt-get build-dep -y -qq . 2>&1 | tail -2 || true
dpkg-buildpackage -us -uc -sa 2>&1 | tail -40
cd .. && echo "== lintian" && lintian -I --pedantic openrgb_*.deb openrgb_*.dsc 2>&1 | head -60 > lintian.txt; cat lintian.txt
chown -R $HOST_UID:$HOST_UID /out; ls /out/work
'
