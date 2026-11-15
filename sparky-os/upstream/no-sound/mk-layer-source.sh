#!/bin/bash
# Sparky Stereo OS: the +lc1 source of stereo-layer 1.21.0-1 (ORDER 579) from a clone of the layer at the commit that carries
# debian/changelog's 1.21.0-1 entry, on the earlier +lc1 source's Lean Code toolkit and preserve plan.
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Usage: mk-layer-source.sh OUT LAYER_CLONE COMMIT PREVIOUS_DSC
# The orig tarball is the commit's tree without debian/ (git archive), as for every earlier version; the plain source is packed
# next to it, then lean.debian_prepare adds the toolkit at 1.21.0-1+lc1 with the earlier source's preserve plan.
set -euo pipefail
# the sources are the same bytes under any umask: extraction by tar and dpkg-source follows it, so the recipe fixes it
umask 022
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
CLONE=$(cd "$2" && pwd) REV=$3 PREV=$(cd "$(dirname "$4")" && pwd)/$(basename "$4")
V=1.21.0
export SOURCE_DATE_EPOCH=$(git -C "$CLONE" log -1 --format=%ct "$REV")
W=$(mktemp -d "$OUT/.work.XXXXXX")
test "$(git -C "$CLONE" show "$REV":debian/changelog | head -1)" = "stereo-layer ($V-1) unstable; urgency=medium"
git -C "$CLONE" archive --format=tar --prefix="stereo-layer-$V/" "$REV" -- . ':!debian' | tar -x -C "$W"
python3 "$TREE/sparky-os/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$W/stereo-layer-$V"
(cd "$W" && tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner -cf - "stereo-layer-$V" | xz -9 > "stereo-layer_$V.orig.tar.xz")
mkdir -p "$W/plain" && cp "$W/stereo-layer_$V.orig.tar.xz" "$W/plain/"
tar -xf "$W/plain/stereo-layer_$V.orig.tar.xz" -C "$W/plain"
git -C "$CLONE" archive --format=tar --prefix="stereo-layer-$V/" "$REV" debian | tar -x -C "$W/plain"
python3 "$TREE/sparky-os/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$W/plain/stereo-layer-$V"
(cd "$W/plain" && dpkg-source -b "stereo-layer-$V" >/dev/null)
# the earlier source's preserve plan, byte for byte
dpkg-source -x --no-check "$PREV" "$W/prev" >/dev/null
python3 "$TREE/sparky-os/repo/plain-from-lc.py" --save-plan "$W/plan.json" "$W/prev" >/dev/null
mkdir -p "$W/lc" && cp "$W/plain/stereo-layer_$V.orig.tar.xz" "$W/plain/stereo-layer_$V-1.dsc" "$W/plain/stereo-layer_$V-1.debian.tar.xz" "$W/lc/"
dpkg-source -x --no-check "$W/lc/stereo-layer_$V-1.dsc" "$W/lc/source" >/dev/null
PYTHONPATH="$TREE/sparky-os" python3 -m lean.debian_prepare "$W/lc/source" "$V-1+lc1" --toolkit "$TREE/sparky-os" --preserve-plan "$W/plan.json"
python3 "$TREE/sparky-os/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$W/lc/source"
rm -f "$W/lc/stereo-layer_$V-1.dsc" "$W/lc/stereo-layer_$V-1.debian.tar.xz"
(cd "$W/lc/source" && dpkg-source -b . >/dev/null)
ls "$W/lc"
mkdir -p "$OUT/stereo-layer" && cp "$W/lc/"stereo-layer_*.dsc "$W/lc/"stereo-layer_*.debian.tar.xz "$W/lc/"stereo-layer_*.orig.tar.xz "$OUT/stereo-layer/"
cp "$W/plain/stereo-layer_$V-1.dsc" "$OUT/stereo-layer/plain-stereo-layer_$V-1.dsc"
rm -rf "$W"
