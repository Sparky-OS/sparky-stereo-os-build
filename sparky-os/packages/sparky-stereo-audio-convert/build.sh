#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/06
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-audio-convert (hand-assembled .deb, Paweł's formula).
# Last update 2026/10/29
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the output directory}
VERSION=0.1.4+lc1
PKG=sparky-stereo-audio-convert
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/usr/share/kio/servicemenus" "$D/usr/share/sparky/sparky-audio-convert" "$D/usr/share/doc/$PKG"
install -m755 "$HERE/bin/sparky-audio-convert" "$D/usr/bin/"
install -m644 "$HERE/share/kio/servicemenus/sparky-audio-convert.desktop" "$D/usr/share/kio/servicemenus/"
install -m644 "$HERE"/lang/* "$D/usr/share/sparky/sparky-audio-convert/"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<X
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: bash, ffmpeg, kdialog
Recommends: dolphin
Section: Utilities
Priority: optional
Homepage: https://sparkylinux.org
Description: Dolphin menu to convert audio files, tags kept
  Adds "Convert audio to" (FLAC, Ogg Vorbis, Opus, MP3, WAV) to Dolphin's right click menu
  for audio files, through FFmpeg, with the tags kept and a KDE notification when done.
  The edition's answer to the dropped soundKonverter.
X
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
sync
