#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-declarative, +stereo3d3 (ORDER 555): the published +stereo3d2+lc1 source
# unpacked, patch s3-0001 appended to its series, and the changelog entry of the plain version then the Lean Code entry on
# top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte identical
# suffix. build.sh and build-in-container.sh stay the +stereo3d1 recipe (from Debian's 6.11.2+dfsg-3). +stereo3d2 was made
# the same way as this one, by ORDER 311's run (lc-successor.py --in-place with an overlay holding s2-0001 and the series,
# Lean Code toolkit 0.1.28); its entry is kept in changelog-stereo3d2.txt as the published source has it.
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d2+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
# The binary packages are built from the new .dsc with release/build-from-lc-dsc.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.11.2+dfsg-3+stereo3d2+lc1' ] || { echo "the published source must be 6.11.2+dfsg-3+stereo3d2+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/qt6-declarative-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
p=s3-0001-Quick-draw-a-frame-made-for-an-expose-as-a-pair-too.patch
grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the published source already has $p" >&2; exit 2; }
cp "$HERE/patches/$p" "$W/overlay/patches/"
echo "$p" >> "$W/overlay/patches/series"
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d3.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 6.11.2+dfsg-3+stereo3d3 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
