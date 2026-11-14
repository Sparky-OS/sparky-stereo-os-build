#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 576: the next +lc1 source of dolphin, whose stereo thumbnails lie under their holes to the device
# pixel at a scale that is not whole, after the way of ../per-file-choice-551/next-source.sh: the published +lc1 source
# unpacked; this folder's patch appended to its series; the layer's version in Build-Depends; and the plain entry, then the
# Lean Code entry, on top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a
# byte identical suffix of the new one.
#   next-source.sh PUBLISHED.dsc OUT
# Run it where dpkg-source is (the Lean Code migration container; round.sh does).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
PUBLISHED_VERSION=$(sed -n 's/^Version: //p' "$DSC")
[ "${PUBLISHED_VERSION#*:}" = '26.08.0-1+stereo3d7+lc1' ] || { echo "dolphin: the successor is made from +stereo3d7+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
NEXT=4:26.08.0-1+stereo3d8
W=$(mktemp -d "${TMPDIR:-/tmp}/thumbnails-576-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
cp "$HERE/patches/dolphin-stereo-thumbnails-on-device-pixels.patch" "$W/overlay/patches/"
echo dolphin-stereo-thumbnails-on-device-pixels.patch >> "$W/overlay/patches/series"
mapfile -t items < <(python3 - "$HERE/changelog/dolphin.items" <<'PY'
import sys
# one item per paragraph (blank line between), its lines joined by a space
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
# the eyes' canvas is the layer's from 1.18.1 on; with an older layer the build stops (the rules pass
# -DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON since +stereo3d7)
python3 "$REPO/lc-successor.py" --in-place --next "$NEXT" "${args[@]}" \
	--depends 'Build-Depends: libstereo-layer-dev (>= 1.18.0),' 'Build-Depends: libstereo-layer-dev (>= 1.18.1),' \
	--overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
