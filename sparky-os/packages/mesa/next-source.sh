#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/09
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of mesa, +stereo3d20 (ORDER 489): the published +stereo3d19+lc1 source unpacked, patches 0035 and
# 0036 appended to its series, the two zink tests added to debian/tests, and the changelog entry of the plain version then the Lean Code
# entry on top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte identical suffix.
# prepare-source.sh stays the +stereo3d19 recipe (it starts from the +stereo3d17 source).
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d19+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '26.1.6-1+stereo3d19+lc1' ] || { echo "the published source must be 26.1.6-1+stereo3d19+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/mesa-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches" "$W/overlay/tests"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0035-zink-keep-the-descriptor-binding-of-the-64-bit-storage-buffer-view.patch \
         0036-zink-bind-the-whole-last-block-of-a-sparse-buffer.patch; do
	grep -qxF "$p" "$W/published/debian/patches/series" && continue
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
cp "$HERE/tests/egl-surfaceless-ssbo64.c" "$HERE/tests/egl-surfaceless-sparse-tail.c" "$HERE/zink-surfaceless" "$W/overlay/tests/"
cat "$W/published/debian/tests/control" - > "$W/overlay/tests/control" <<'CTL'

Tests: zink-ssbo64
Test-Command: debian/tests/zink-surfaceless egl-surfaceless-ssbo64
Depends: build-essential, libegl1-mesa-dev, libgl1-mesa-dev, libegl-mesa0, libgl1-mesa-dri, mesa-vulkan-drivers
Restrictions: skippable

Tests: zink-sparse-tail
Test-Command: debian/tests/zink-surfaceless egl-surfaceless-sparse-tail
Depends: build-essential, libegl1-mesa-dev, libgl1-mesa-dev, libegl-mesa0, libgl1-mesa-dri, mesa-vulkan-drivers
Restrictions: skippable
CTL
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d20.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 26.1.6-1+stereo3d20 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
