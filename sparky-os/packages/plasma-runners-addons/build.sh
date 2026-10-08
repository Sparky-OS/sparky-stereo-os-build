#!/bin/bash
# Build Debian's kdeplasma-addons with the edition's on-demand currency runner.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the pending package directory}
BUILD_ROOT=${BUILD_ROOT:?Set BUILD_ROOT to a disposable build directory}
BASE_VERSION=4:6.7.4-1
VERSION=4:6.7.4-1+stereo3d1
mkdir -p "$BUILD_ROOT" "$OUT/source"
cd "$BUILD_ROOT"
DEBIAN_FRONTEND=noninteractive apt-get -y source "kdeplasma-addons=$BASE_VERSION"
cd kdeplasma-addons-6.7.4
cp "$HERE/currency-on-demand.patch" debian/patches/
printf '%s\n' currency-on-demand.patch >> debian/patches/series
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
dch --newversion "$VERSION" --distribution UNRELEASED \
    'Refresh currency rates only for a currency conversion query; keep all local units and currency conversion available.'
export DEB_BUILD_OPTIONS='nocheck parallel=4' DEB_BUILD_PROFILES=nocheck
dpkg-buildpackage -us -uc -j4
cd ..
for archive in ./*.deb; do
    cp "$archive" "$OUT/"
done
cp ./*.dsc ./*.orig.tar.* ./*.debian.tar.* "$OUT/source/"
