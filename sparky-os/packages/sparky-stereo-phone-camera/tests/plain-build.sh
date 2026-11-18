#!/bin/bash
# Builds the package with dpkg-buildpackage in a container that has debhelper (no network), then runs lintian.
# Usage (inside the container, as a non-root user): plain-build.sh PACKAGE_DIR OUT_DIR
set -euo pipefail
PKG=$(realpath "$1") OUT=$(realpath "$2")
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
W=$(mktemp -d)
cp -a "$PKG" "$W/sparky-stereo-phone-camera"
cd "$W/sparky-stereo-phone-camera"
dpkg-buildpackage -us -uc -b >"$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
cp "$W"/*.deb "$W"/*.buildinfo "$W"/*.changes "$OUT"/
lintian --no-cfg -I "$OUT"/sparky-stereo-phone-camera_0.1.0_all.deb >"$OUT/lintian.txt" 2>&1 || true
dpkg-deb -c "$OUT"/sparky-stereo-phone-camera_0.1.0_all.deb | awk '{print $1, $3, $6}' >"$OUT/contents.txt"
dpkg-deb -f "$OUT"/sparky-stereo-phone-camera_0.1.0_all.deb Depends >"$OUT/depends.txt"
echo built
