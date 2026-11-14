#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of xwayland, 24.1.15 +stereo3d2 (ORDER 561): the 24.1.15 +stereo3d1+lc1 source
# (rebase-source.py, ORDER 562) unpacked, patch 0013 appended to its series, and the changelog entry of the plain version
# then the Lean Code entry on top of that source's history (repo/lc-successor.py --in-place --overlay), so the old
# changelog stays a byte identical suffix. No build dependency changes: the suite's test, which 0013 extends, already runs.
#   next-source-24.1.15-stereo3d2.sh PREVIOUS.dsc OUT
#   PREVIOUS.dsc: the 2:24.1.15-1+stereo3d1+lc1 source (its orig tarball beside it)
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
[ "$(sed -n 's/^Version: //p' "$DSC")" = '2:24.1.15-1+stereo3d1+lc1' ] || { echo "the source must be 2:24.1.15-1+stereo3d1+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/xwayland-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0013-xwayland-present-a-copied-present-keeps-both-eyes-of.patch; do
	grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the source already has $p" >&2; exit 2; }
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
mapfile -t items < <(python3 - "$HERE/changelog-24.1.15-stereo3d2.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 2:24.1.15-1+stereo3d2 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
