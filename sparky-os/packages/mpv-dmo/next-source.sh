#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of mpv-dmo, +stereo3d12 (row 137): the published +stereo3d11+lc1 source
# (row 835) unpacked, patch 0064 (the render API's stereo view parameter, ours: upstream has none) appended to its
# series, the changelog entry of the
# plain version then the Lean Code entry on top of that history (repo/lc-successor.py --in-place --overlay), so the old
# changelog stays a byte identical suffix. +stereo3d11 was made the same way from +stereo3d10 with patches 0062 and
# 0063 (upstream's 3847a8157f6e by Dudemanguy and f4d13e1c2c91 by llyyr), +stereo3d10 from +stereo3d9 with patch 0061.
#   next-source.sh PREDECESSOR.dsc OUT
#   PREDECESSOR.dsc: the published +stereo3d11+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '1:0.41.0-dmo9+stereo3d11+lc1' ] || { echo "the source must be 1:0.41.0-dmo9+stereo3d11+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/mpv-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0064-render-add-MPV_RENDER_PARAM_STEREO_VIEW-one-view-of-a-stereo-video.patch; do
	grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the source already has $p" >&2; exit 2; }
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d12.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 1:0.41.0-dmo9+stereo3d12 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
