#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-base, +stereo3d16 (ORDER 146b): the published +stereo3d15+lc1 source unpacked,
# this folder's patch appended to its series, and the changelog entry of the plain version then the Lean Code entry on top of the
# published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte identical suffix.
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d15+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.11.2+dfsg-5+stereo3d15+lc1' ] || { echo "the published source must be 6.11.2+dfsg-5+stereo3d15+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/qt6-base-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | xxd -p)" = 0a ] || echo >> "$W/overlay/patches/series"
for p in "$HERE"/patches/*.patch; do
	grep -qxF "$(basename "$p")" "$W/published/debian/patches/series" && continue
	cp "$p" "$W/overlay/patches/"
	basename "$p" >> "$W/overlay/patches/series"
done
mapfile -t items < <(python3 - "$HERE/changelog/stereo3d16.items" <<'PY'
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 6.11.2+dfsg-5+stereo3d16 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
