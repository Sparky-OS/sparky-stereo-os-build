#!/bin/bash
# Rebuild Debian's dolphin with the edition's Dolphin workflow changes.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the pending package directory}
BUILD_ROOT=${BUILD_ROOT:?Set BUILD_ROOT to a disposable build directory}
BASE_VERSION=4:26.08.0-1
VERSION=4:26.08.0-1+stereo3d1
mkdir -p "$BUILD_ROOT" "$OUT/source"
cd "$BUILD_ROOT"
DEBIAN_FRONTEND=noninteractive apt-get -y source "dolphin=$BASE_VERSION"
cd dolphin-26.08.0
mkdir -p debian/patches
cp "$HERE/desktop-workflows.patch" debian/patches/
printf '%s\n' desktop-workflows.patch >>debian/patches/series
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
dch --newversion "$VERSION" --distribution UNRELEASED \
    'Expose Reload, preview non-executable shell scripts before terminal execution, and open removable-drive formatting.'
export DEB_BUILD_OPTIONS='nocheck parallel=4' DEB_BUILD_PROFILES=nocheck
dpkg-buildpackage -us -uc -j4
cd ..
for archive in ./*.deb; do
    cp "$archive" "$OUT/"
done
cp ./*.dsc ./*.orig.tar.* ./*.debian.tar.* "$OUT/source/"
