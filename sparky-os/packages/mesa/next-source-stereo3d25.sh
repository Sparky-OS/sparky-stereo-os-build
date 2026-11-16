#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
# +stereo3d25 from the one +24+lc1 source, preserving its history and Lean Code toolkit.
# ORDER 623: the Vulkan stereo layer gives an X11 window its pair where the X server has no DRI3 (patch 0041); the
# layer's catalogs take its own messages (debian/lang-layer: LOCAL1 and LOCAL2 from lang/, LOCAL3 and LOCAL4 from
# lang-layer/; debian-stereo3d25.py changes the layer's catalog line in debian/rules).
# Usage: next-source-stereo3d25.sh PREVIOUS.dsc OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '26.1.6-1+stereo3d24+lc1' ] || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/mesa-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches" "$W/overlay/lang-layer"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
p=0041-vulkan-stereo-layer-x11-pair-without-dri3.patch
if grep -qxF "$p" "$W/overlay/patches/series"; then echo "$p is already in the previous series" >&2; exit 2; fi
cp "$HERE/patches/$p" "$W/overlay/patches/"
echo "$p" >> "$W/overlay/patches/series"
for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
	{ sed -n '/^LOCAL[12]=/p' "$HERE/lang/$l"; cat "$HERE/lang-layer/$l"; } > "$W/overlay/lang-layer/$l"
done
python3 "$HERE/debian-stereo3d25.py" "$W/published/debian" "$W/overlay"
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d25.txt" <<'PY'
import sys,re
text=open(sys.argv[1]).read().split('\n\n',1)[1]
for p in re.split(r'(?m)^  \* ',text.strip('\n'))[1:]: print(' '.join(l.strip() for l in p.splitlines()))
PY
)
args=(); for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 26.1.6-1+stereo3d25 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
