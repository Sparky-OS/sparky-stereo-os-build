#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.2.0+lc1
PACKAGE=sparky-stereo-game-performance
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.game-performance.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
install -Dm755 "$HERE/bin/game-performance" "$D/usr/bin/game-performance"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: bash, power-profiles-daemon (>= 0.30)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Hold the performance profile while a game runs
  Launch a command with power-profiles-daemon's performance hold.
  The daemon restores its selected profile after the command exits.
  Hardware without a performance profile runs the command unchanged.
EOF
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
