#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of xwayland, +stereo3d5 (ORDER 560): the published +stereo3d4+lc1 source unpacked,
# patches 0010 to 0012 appended to its series, the test's build dependencies added to debian/control, and the changelog
# entry of the plain version then the Lean Code entry on top of the published history (repo/lc-successor.py --in-place
# --overlay), so the old changelog stays a byte identical suffix. prepare-source.sh and build-in-container.sh stay the
# +stereo3d4 recipe (from the published +stereo3d3+lc1 source).
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d4+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
# The binary package is built from the new .dsc with release/build-from-lc-dsc.sh; its log must show the suite's line
# "stereo pair without glamor OK" (a SKIP there means weston was missing: that is not a pass).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '2:24.1.13-1+stereo3d4+lc1' ] || { echo "the published source must be 2:24.1.13-1+stereo3d4+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/xwayland-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0010-xwayland-shm-give-a-pixmap-that-holds-both-eyes-of-a.patch \
	0011-xwayland-present-damage-both-eyes-of-a-flipped-stere.patch \
	0012-test-a-stereo-window-s-pair-reaches-the-compositor-w.patch; do
	grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the published source already has $p" >&2; exit 2; }
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
# the test of 0012 runs in the build: its compositor and the three xcb development packages, before the published line
# that ends the field (wayland-protocols and the Lean Code build dependencies)
python3 - "$W/published/debian/control" "$W/overlay/control" <<'PY'
import sys
text = open(sys.argv[1], encoding='utf-8').read()
anchor = ' wayland-protocols, gcc, node-acorn, nodejs, perl, python3, python3-yaml\n'
added = ' libxcb-composite0-dev <!nocheck>,\n libxcb-present-dev <!nocheck>,\n libxcb1-dev <!nocheck>,\n weston <!nocheck>,\n'
if text.count(anchor) != 1 or 'weston' in text:
    sys.exit('the published debian/control is not the one this recipe knows')
open(sys.argv[2], 'w', encoding='utf-8').write(text.replace(anchor, added + anchor))
PY
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d5.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 2:24.1.13-1+stereo3d5 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
