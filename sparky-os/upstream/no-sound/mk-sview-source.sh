#!/bin/bash
# Sparky Stereo OS: the +lc1 source of sview 26.9+stereo3d6 (ORDER 579) from the commit of the sView fork that carries
# debian/changelog's 26.9+stereo3d6 entry; the same steps as packages/sview/build-in-container.sh, on the host (no package is built).
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Usage: mk-sview-source.sh OUT FORK_CLONE COMMIT
set -euo pipefail
# the sources are the same bytes under any umask: extraction by tar and dpkg-source follows it, so the recipe fixes it
umask 022
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
CLONE=$(cd "$2" && pwd) REV=$3
NEWV=26.9+stereo3d6
export SOURCE_DATE_EPOCH=$(git -C "$CLONE" log -1 --format=%ct "$REV")
test "$(git -C "$CLONE" show "$REV":debian/changelog | head -1)" = "sview ($NEWV) UNRELEASED; urgency=medium"
W=$(mktemp -d "$OUT/.work.XXXXXX")
mkdir -p "$W/plain" && cd "$W/plain"
git -C "$CLONE" archive --format=tar --prefix="sview-$NEWV/" "$REV" | tar -x
touch -d "@$SOURCE_DATE_EPOCH" "sview-$NEWV"
python3 "$TREE/sparky-os/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "sview-$NEWV"
dpkg-source -b "sview-$NEWV" >/dev/null
rm -rf "sview-$NEWV"
mkdir -p "$W/lc" && cp "$W/plain/"* "$W/lc/" && cd "$W/lc"
dpkg-source -x "sview_$NEWV.dsc" source >/dev/null
PYTHONPATH="$TREE/sparky-os" python3 -m lean.debian_prepare "$W/lc/source" "$NEWV+lc1" --toolkit "$TREE/sparky-os"
python3 "$TREE/sparky-os/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$W/lc/source"
rm -f "sview_$NEWV.dsc" "sview_$NEWV.tar.xz"
(cd source && dpkg-source -b . >/dev/null)
mkdir -p "$OUT/sview" && cp "$W/lc/"sview_*+lc1* "$OUT/sview/"
cp "$W/plain/sview_$NEWV.dsc" "$OUT/sview/plain-sview_$NEWV.dsc"
rm -rf "$W"
ls "$OUT/sview"
