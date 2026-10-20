#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.xpadneo-dkms.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/xpadneo-dkms
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/xpadneo-dkms"
install -m644 "$HERE/copyright" "$D/usr/share/doc/xpadneo-dkms/copyright"
source "$HERE/payload.sh"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: xpadneo-dkms
Version: 0.1.0+lc1
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: dkms (>= 3.0), udev
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Xbox Bluetooth controller DKMS driver for Sparky Stereo OS
  Hardware support selected by sparky-stereo-hardware after detection.
EOF
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
sync
