#!/bin/bash
# Build Debian's plasma-workspace with the edition's leave-screen recovery actions.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the pending package directory}
BUILD_ROOT=${BUILD_ROOT:?Set BUILD_ROOT to a disposable build directory}
BASE_VERSION=4:6.7.4-2
VERSION=4:6.7.4-2+stereo3d1
mkdir -p "$BUILD_ROOT" "$OUT/source"
cd "$BUILD_ROOT"
DEBIAN_FRONTEND=noninteractive apt-get -y source "plasma-workspace=$BASE_VERSION"
cd plasma-workspace-6.7.4
mkdir -p debian/patches
cp "$HERE/"{logout-recovery-actions,upstream-qtqml-links}.patch debian/patches/
printf '%s\n' logout-recovery-actions.patch upstream-qtqml-links.patch >>debian/patches/series
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
dch --newversion "$VERSION" --distribution UNRELEASED \
    'Offer System Monitor and interactive frozen-window closing in the leave screen; retain all session actions.'
dch --append 'Backport upstream Qt QML linkage for current KDE Frameworks dependencies.'
export DEB_BUILD_OPTIONS='nocheck parallel=4' DEB_BUILD_PROFILES=nocheck
dpkg-buildpackage -us -uc -j4
cd ..
for archive in ./*.deb; do
    cp "$archive" "$OUT/"
done
cp ./*.dsc ./*.orig.tar.* ./*.debian.tar.* "$OUT/source/"
