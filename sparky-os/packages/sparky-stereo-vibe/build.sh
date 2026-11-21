#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the output directory}
PKG=sparky-stereo-vibe
VERSION=0.1.0+lc1
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -r "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/lib/sparky-stereo/vibe" "$D/usr/share/sparky-stereo/vibe/presets" "$D/usr/share/doc/$PKG"
python3 "$HERE/../sparky-stereo-integration/make-pack.py" "$HERE/pack.json" "$D"
install -m755 "$HERE/bin/seed" "$HERE/bin/captions" "$D/usr/lib/sparky-stereo/vibe/"
install -m644 "$HERE/presets/"*.json "$D/usr/share/sparky-stereo/vibe/presets/"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
cat > "$D/DEBIAN/control" <<X
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Depends: python3, kdialog, sparky-stereo-integration (>= 0.1.5), sparky-stereo-graphics
Enhances: vibe
Section: sound
Priority: optional
Homepage: https://sparkylinux.org
Description: Vibe presets and a Dolphin action to make captions
 Seeds Vibe settings once for each account and creates a sibling SRT from
 a local media file using the installed speech model. Downloads nothing.
X
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums)
A=$W/authoring
COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$A"
mkdir -p "$A/build-tools"
cp "$COPY" "$A/build-tools/"
cp "$HERE/../sparky-stereo-integration/make-pack.py" "$A/make-pack.py"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$A"
