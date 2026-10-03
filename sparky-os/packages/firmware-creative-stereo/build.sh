#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.firmware-creative-stereo.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/firmware-creative-stereo
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/firmware-creative-stereo"
install -m644 "$HERE/copyright" "$D/usr/share/doc/firmware-creative-stereo/copyright"
source "$HERE/payload.sh"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: firmware-creative-stereo
Version: 20261003~sparky9~0
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Creative CA0132 DSP firmware for Sparky Stereo OS
  Hardware support selected by sparky-stereo-hardware after detection.
EOF
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/firmware-creative-stereo_20261003~sparky9~0_all.deb"
sync
