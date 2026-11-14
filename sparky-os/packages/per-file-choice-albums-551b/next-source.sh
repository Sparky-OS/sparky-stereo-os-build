#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551b: the next +lc1 source of koko, kphotoalbum or digikam with the per-file 3D choice of the
# stereo layer (its one menu and its shared store), after the way of ../per-file-choice-551/next-source.sh: the published
# +lc1 source unpacked; this folder's patches appended to its series; the layer's version in Build-Depends; and the plain
# entry, then the Lean Code entry, on top of the published history (repo/lc-successor.py --in-place --overlay), so the
# old changelog stays a byte identical suffix of the new one.
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
# Each of the three is built against the layer that holds the menu's QML form and the store, and stops when it is
# older: the version in Build-Depends, and CMake's own switch -DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON, which the
# published rules of all three already pass (without it an older libstereo-layer-dev is "not found", CMake prints no
# error and the program is built without stereo, ORDER 512).
case $PKG in
koko)
	[ "$PUBLISHED_VERSION" = '26.04.0-1+stereo3d1+lc1' ] || { echo "koko: the successor is made from +stereo3d1+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=26.04.0-1+stereo3d2
	PATCHES=(koko-shared-per-file-choice.patch koko-stereo-translations-de-es.patch)
	depends=(--depends 'libstereo-layer-dev (>= 1.4.0),' 'libstereo-layer-dev (>= 1.19.0),')
	;;
kphotoalbum)
	[ "$PUBLISHED_VERSION" = '6.2.0-1+stereo3d1+lc1' ] || { echo "kphotoalbum: the successor is made from +stereo3d1+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=6.2.0-1+stereo3d2
	PATCHES=(kphotoalbum-shared-per-file-choice.patch kphotoalbum-stereo-translations-de-es.patch)
	depends=(--depends 'libstereo-layer-dev (>= 1.4.0),' 'libstereo-layer-dev (>= 1.19.0),')
	;;
digikam)
	[ "${PUBLISHED_VERSION#*:}" = '9.1.0-1+stereo3d3+lc1' ] || { echo "digikam: the successor is made from +stereo3d3+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:9.1.0-1+stereo3d4
	PATCHES=(digikam-shared-per-file-choice.patch)
	depends=(--depends 'libstereo-layer-dev (>= 1.0.2),' 'libstereo-layer-dev (>= 1.19.0),')
	;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/per-file-choice-albums-XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
# the switch must be in the published rules: this recipe relies on it and does not add it
grep -q -- '-DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON' "$W/published/debian/rules" || { echo "$PKG: debian/rules does not require the stereo layer at configure time" >&2; exit 2; }
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
for p in "${PATCHES[@]}"; do
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
# The stereo functions this version stops calling on purpose, each with its reason: the link gate blocks a lost stereo
# import unless the source declares it (lean/archive.md), so a program built without stereo by accident still stops.
[ ! -f "$HERE/retired-stereo-imports/$PKG" ] || cp "$HERE/retired-stereo-imports/$PKG" "$W/overlay/sparky-lean-retired-stereo-imports"
mapfile -t items < <(python3 - "$HERE/changelog/$PKG.items" <<'PY'
import sys
# one item per paragraph (blank line between), its lines joined by a space
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next "$NEXT" "${args[@]}" "${depends[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
