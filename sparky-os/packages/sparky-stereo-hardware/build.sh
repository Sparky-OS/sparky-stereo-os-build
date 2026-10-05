#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.sparky-stereo-hardware.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/sparky-stereo-hardware
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/sparky-stereo-hardware"
install -m644 "$HERE/copyright" "$D/usr/share/doc/sparky-stereo-hardware/copyright"
source "$HERE/payload.sh"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: sparky-stereo-hardware
Version: 0.1.2
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: apt, bash, ca-certificates, coreutils, curl, grep, isenkram-cli, kmod, laptop-detect, lm-sensors, nvidia-detect, pciutils, python3, sed, sparky-remsu, sparky-xterm, udev, usbutils, util-linux, yad
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Detect and configure matched hardware for Sparky Stereo OS
  Hardware support selected by sparky-stereo-hardware after detection.
EOF
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/sparky-stereo-hardware_0.1.2_all.deb"
sync
