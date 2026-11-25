#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, queue row 81 part D: the next +lc1 source of kpipewire, whose encoded stream can keep a constant frame
# rate on a still source (a Cast receiver's player waits for the next picture of a live stream), after the way of
# ../not-3d-thumbnail-581/next-source.sh: the published +lc1 source unpacked; this folder's patch appended to its series;
# the two new symbols added to libkpipewirerecord6.symbols at the version that brings them; and the plain entry, then the
# Lean Code entry, on top of the published history (repo/lc-successor.py --in-place --overlay).
#   next-source.sh PUBLISHED.dsc OUT
# Run it where dpkg-source is (the Lean Code migration container, as ../not-3d-thumbnail-581/round.sh does).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
PUBLISHED_VERSION=$(sed -n 's/^Version: //p' "$DSC")
[ "${PUBLISHED_VERSION#*:}" = '6.7.4-1+stereo3d8+lc1' ] || { echo "kpipewire: the successor is made from +stereo3d8+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
NEXT=6.7.4-1+stereo3d9
W=$(mktemp -d "${TMPDIR:-/tmp}/kpipewire-81d-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
cp "$HERE/patches/kpipewire-constant-framerate.patch" "$W/overlay/patches/"
echo kpipewire-constant-framerate.patch >> "$W/overlay/patches/series"
# the two symbols the patch adds, at the version that brings them (the edition's own symbols are kept this way)
cp "$W/published/debian/libkpipewirerecord6.symbols" "$W/overlay/libkpipewirerecord6.symbols"
printf ' _ZN25PipeWireBaseEncodedStream20setConstantFramerateEb@Base %s\n _ZNK25PipeWireBaseEncodedStream17constantFramerateEv@Base %s\n' \
    "$NEXT" "$NEXT" >> "$W/overlay/libkpipewirerecord6.symbols"
mapfile -t items < <(python3 - "$HERE/changelog/kpipewire.items" <<'PY'
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --reapply-patches --next "$NEXT" "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
