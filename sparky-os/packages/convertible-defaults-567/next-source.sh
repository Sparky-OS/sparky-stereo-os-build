#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 567: the next +lc1 source of plasma-workspace or plasma-desktop with the panels that hide by
# themselves in tablet mode, after the way of ../per-file-choice-551/next-source.sh: the published +lc1 source unpacked;
# this folder's patch placed before the translation patches of its series, and plasma-desktop's new translation patch
# last; the plain entry, then the Lean Code entry, on top of the published history (repo/lc-successor.py --in-place
# --overlay), so the old changelog stays a byte identical suffix of the new one.
#   next-source.sh PACKAGE PUBLISHED.dsc OUT
# Run it where dpkg-source is (the Lean Code migration container; round.sh does).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
PKG=$1 DSC=$(readlink -f "$2") OUT=$3
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
PUBLISHED_VERSION=$(sed -n 's/^Version: //p' "$DSC")
PO=()
case $PKG in
plasma-workspace)
	[ "${PUBLISHED_VERSION#*:}" = '6.7.4-2+stereo3d7+lc1' ] || { echo "plasma-workspace: the successor is made from +stereo3d7+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:6.7.4-2+stereo3d8
	PATCHES=(plasma-workspace-panels-hide-in-tablet-mode.patch)
	;;
plasma-desktop)
	[ "${PUBLISHED_VERSION#*:}" = '6.7.4-1+stereo3d3+lc1' ] || { echo "plasma-desktop: the successor is made from +stereo3d3+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:6.7.4-1+stereo3d4
	PATCHES=(plasma-desktop-tablet-mode-panels-switch.patch)
	PO=(plasma-desktop-tablet-mode-panels.po.patch)
	;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/convertible-defaults-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
for p in "${PATCHES[@]}"; do cp "$HERE/patches/$p" "$W/overlay/patches/"; done
for p in "${PO[@]}"; do cp "$HERE/../../translations/$p" "$W/overlay/patches/"; done
# the code patch goes before the first translation patch of the published series (a translation patch is named
# last, ORDER 391), the new translation patch after them all
python3 - "$W/published/debian/patches/series" "$W/overlay/patches/series" "${#PATCHES[@]}" "${PATCHES[@]}" "${PO[@]}" <<'PY'
import sys
source, target, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
code, po = sys.argv[4:4 + count], sys.argv[4 + count:]
lines = open(source, encoding='utf-8').read().split('\n')
while lines and lines[-1] == '':
    lines.pop()
for name in code + po:
    if name in lines:
        sys.exit(f'{source}: {name} is in the published series already')
first = next((i for i, line in enumerate(lines) if line.endswith('.po.patch')), len(lines))
lines[first:first] = code
lines += po
open(target, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
PY
mapfile -t items < <(python3 - "$HERE/changelog/$PKG.items" <<'PY'
import sys
# one item per paragraph (blank line between), its lines joined by a space
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next "$NEXT" "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
