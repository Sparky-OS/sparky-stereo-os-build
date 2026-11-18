#!/bin/bash
# Builds the package from the pinned orig archive with dpkg-buildpackage, in a container that has the build dependencies (no network).
# Usage (inside the container, as a non-root user): plain-build.sh ORIG_DIR DEBIAN_DIR OUT_DIR
set -euo pipefail
ORIG=$(realpath "$1") DEB=$(realpath "$2") OUT=$(realpath "$3")
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
W=$(mktemp -d)
cp "$ORIG"/droidcam_2.1.7.orig.tar.xz "$W"/
tar -xJf "$W"/droidcam_2.1.7.orig.tar.xz -C "$W"
cp -a "$DEB" "$W/droidcam-2.1.7/debian"
cd "$W/droidcam-2.1.7"
dpkg-buildpackage -us -uc -b >"$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }
cp "$W"/*.deb "$W"/*.buildinfo "$W"/*.changes "$OUT"/
lintian --no-cfg -I "$OUT"/droidcam_2.1.7-1_amd64.deb >"$OUT/lintian.txt" 2>&1 || true
dpkg-deb -c "$OUT"/droidcam_2.1.7-1_amd64.deb | awk '{print $1, $3, $6}' >"$OUT/contents.txt"
dpkg-deb -f "$OUT"/droidcam_2.1.7-1_amd64.deb Depends >"$OUT/depends.txt"
echo built
