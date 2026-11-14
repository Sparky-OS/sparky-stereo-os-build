#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# +stereo3d23 from the one +22+lc1 source, preserving its history and Lean Code toolkit.
# Shared copied-present rule for GLX, EGL X11 and the Vulkan stereo layer; each library's messages belong to its package.
# Usage: next-source-stereo3d23.sh PREVIOUS.dsc OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '26.1.6-1+stereo3d22+lc1' ] || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/mesa-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches" "$W/overlay/tests" "$W/overlay/lang-pair"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
p=0039-shared-copied-present-check-for-egl-x11-and-vulkan-layer.patch
cp "$HERE/patches/$p" "$W/overlay/patches/"
echo "$p" >> "$W/overlay/patches/series"
for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
    sed -n '/^LOCAL[12]=/p' "$HERE/lang/$l" > "$W/overlay/lang-pair/$l"
done
cp "$HERE/tests/egl-covered.c" "$HERE/egl-pair-copied" "$W/overlay/tests/"
cat "$W/published/debian/tests/control" - > "$W/overlay/tests/control" <<'CTL'

Tests: egl-pair-copied
Depends: build-essential, libegl1-mesa-dev, libgl1-mesa-dev, libx11-dev, libegl-mesa0, libgl1-mesa-dri, xvfb
Restrictions: skippable
CTL
python3 "$HERE/debian-stereo3d23.py" "$W/published/debian" "$W/overlay"
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d23.txt" <<'PY'
import sys,re
text=open(sys.argv[1]).read().split('\n\n',1)[1]
for p in re.split(r'(?m)^  \* ',text.strip('\n'))[1:]: print(' '.join(l.strip() for l in p.splitlines()))
PY
)
args=(); for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 26.1.6-1+stereo3d23 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
