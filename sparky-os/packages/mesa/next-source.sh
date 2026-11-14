#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/09, last update 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of mesa, +stereo3d21 (ORDER 559): the published +stereo3d20+lc1 source unpacked, patch 0037
# appended to its series, the glx-back-both-eyes test added to debian/tests, and the changelog entry of the plain version then the
# Lean Code entry on top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte
# identical suffix. prepare-source.sh stays the +stereo3d19 recipe (it starts from the +stereo3d17 source).
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d20+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '26.1.6-1+stereo3d20+lc1' ] || { echo "the published source must be 26.1.6-1+stereo3d20+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/mesa-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches" "$W/overlay/tests"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0037-st-mesa-one-draw-buffer-constant-for-several-buffers-takes-the-shaders-own-output.patch; do
	grep -qxF "$p" "$W/published/debian/patches/series" && continue
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
cp "$HERE/tests/glx-draw-buffers.c" "$HERE/glx-back-both-eyes" "$W/overlay/tests/"
cat "$W/published/debian/tests/control" - > "$W/overlay/tests/control" <<'CTL'

Tests: glx-back-both-eyes
Depends: build-essential, libgl1-mesa-dev, libx11-dev, libglx-mesa0, libgl1-mesa-dri, xvfb
Restrictions: skippable
CTL
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d21.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 26.1.6-1+stereo3d21 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
