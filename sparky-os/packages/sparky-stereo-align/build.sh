#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-align (hand-assembled .deb, Paweł's formula): an integration pack, a data pack in the stereo-integrations skill's sense.
# The strings, the pack definition and the Dolphin menu come from gen.py and ../sparky-stereo-integration/make-pack.py.
# Last update 2026/10/24
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the output directory}
VERSION=0.1.0+lc1
PKG=sparky-stereo-align
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
G=$W/gen
mkdir -p "$D/DEBIAN" "$D/usr/lib/sparky-stereo/align" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" "$G"
python3 "$HERE/gen.py" "$G"
python3 "$HERE/../sparky-stereo-integration/make-pack.py" "$G/pack.json" "$D"
install -m755 "$HERE/bin/align" "$D/usr/lib/sparky-stereo/align/align"
install -m644 "$G"/lang/* "$D/usr/share/sparky/$PKG/"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<X
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: python3, python3-pil, sparky-stereo-integration (>= 0.1.0)
Enhances: hugin-tools
Section: Utilities
Priority: optional
Homepage: https://sparkylinux.org
Description: Dolphin menu to align a stereo pair with Hugin
  Adds "Align stereo pair" to Dolphin's right click menu on two pictures, and "Align the two views" on a JPS, MPO or PNS,
  through Hugin's align_image_stack -S. The result is a new JPS, MPO or PNS with its own mark; the original is never touched.
X
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
A=$W/authoring
cp -a "$HERE/." "$A/"
cp "$HERE/../sparky-stereo-integration/make-pack.py" "$A/make-pack.py"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$A"
sync
