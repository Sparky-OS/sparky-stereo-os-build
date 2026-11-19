#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# +stereo3d28 from the one +26+lc1 source (the +27 of the first hand-back was never published), preserving its history and Lean Code toolkit.
# ORDER 50c: a GL child of a window that is not on the screen yet is declared once the window is viewable (patch 0045), a
# child whose window is unmapped or minimised and comes back is declared again (patch 0046), and libudev-dev and
# libxcb-keysyms1-dev are declared build dependencies (debian-changes-stereo3d28.py).
# Usage: next-source-stereo3d28.sh PREVIOUS.dsc OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '26.1.6-1+stereo3d26+lc1' ] || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/mesa-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0045-glx-a-stereo-child-is-declared-once-its-window-is-viewable.patch \
	0046-glx-a-stereo-child-is-declared-again-when-its-window-comes-back.patch; do
	if grep -qxF "$p" "$W/overlay/patches/series"; then echo "$p is already in the previous series" >&2; exit 2; fi
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
python3 "$HERE/debian-changes-stereo3d28.py" "$W/published/debian" "$W/overlay"
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d28.txt" <<'PY'
import sys,re
text=open(sys.argv[1]).read().split('\n\n',1)[1]
for p in re.split(r'(?m)^  \* ',text.strip('\n'))[1:]: print(' '.join(l.strip() for l in p.splitlines()))
PY
)
args=(); for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 26.1.6-1+stereo3d28 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
