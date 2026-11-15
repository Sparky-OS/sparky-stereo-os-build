#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551c: the next +lc1 source of gwenview, koko, kphotoalbum or digikam with the program's own
# "Enable 3D" from the stereo layer (Stereo::Enable3DAction, Enable3DAction in QML) in place of a second "Not 3D", after
# the way of ../per-file-choice-albums-551b/next-source.sh: the given +lc1 source unpacked (gwenview's published +10,
# the staged +2, +2 and +4 of ORDER 551b for the three album programs); this folder's patches appended to its series
# (digiKam's catalogue patch from ../../translations, last); the layer's version in Build-Depends; and the plain entry,
# then the Lean Code entry, on top of that source's history (repo/lc-successor.py --in-place --overlay), so the old
# changelog stays a byte identical suffix of the new one.
#   next-source.sh PACKAGE GIVEN.dsc OUT
# Run it where dpkg-source is (the Lean Code migration container; round.sh does).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
TRANSLATIONS=$(cd "$HERE/../../translations" && pwd)
PKG=$1 DSC=$(readlink -f "$2") OUT=$3
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
GIVEN_VERSION=$(sed -n 's/^Version: //p' "$DSC")
# Each is built against the layer that has Enable3DAction and stops when it is older: the version in Build-Depends,
# and -DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON, which the rules of all four already pass (without it an older
# libstereo-layer-dev is "not found", CMake prints no error and the program is built without stereo, ORDER 512).
case $PKG in
gwenview)
	[ "${GIVEN_VERSION#*:}" = '26.04.0-1+stereo3d10+lc1' ] || { echo "gwenview: the successor is made from +stereo3d10+lc1, not $GIVEN_VERSION" >&2; exit 2; }
	NEXT=4:26.04.0-1+stereo3d11
	PATCHES=("$HERE/patches/gwenview-enable-3d.patch")
	depends=(--depends 'libstereo-layer-dev (>= 1.18.0),' 'libstereo-layer-dev (>= 1.19.2),')
	;;
koko)
	[ "$GIVEN_VERSION" = '26.04.0-1+stereo3d2+lc1' ] || { echo "koko: the successor is made from +stereo3d2+lc1, not $GIVEN_VERSION" >&2; exit 2; }
	NEXT=26.04.0-1+stereo3d3
	PATCHES=("$HERE/patches/koko-enable-3d.patch")
	depends=(--depends 'libstereo-layer-dev (>= 1.19.0),' 'libstereo-layer-dev (>= 1.19.2),')
	;;
kphotoalbum)
	[ "$GIVEN_VERSION" = '6.2.0-1+stereo3d2+lc1' ] || { echo "kphotoalbum: the successor is made from +stereo3d2+lc1, not $GIVEN_VERSION" >&2; exit 2; }
	NEXT=6.2.0-1+stereo3d3
	PATCHES=("$HERE/patches/kphotoalbum-enable-3d.patch")
	depends=(--depends 'libstereo-layer-dev (>= 1.19.0),' 'libstereo-layer-dev (>= 1.19.2),')
	;;
digikam)
	[ "${GIVEN_VERSION#*:}" = '9.1.0-1+stereo3d4+lc1' ] || { echo "digikam: the successor is made from +stereo3d4+lc1, not $GIVEN_VERSION" >&2; exit 2; }
	NEXT=4:9.1.0-1+stereo3d5
	# the catalogue patch last in the series (../../translations/README.md, "Which package carries each patch")
	PATCHES=("$HERE/patches/digikam-enable-3d-and-told-carry.patch" "$TRANSLATIONS/digikam-stereo3d.po.patch")
	depends=(--depends 'libstereo-layer-dev (>= 1.19.0),' 'libstereo-layer-dev (>= 1.19.2),')
	;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/album-programs-551c-XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/given" >/dev/null
grep -q -- '-DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON' "$W/given/debian/rules" || { echo "$PKG: debian/rules does not require the stereo layer at configure time" >&2; exit 2; }
mkdir -p "$W/overlay/patches"
cp "$W/given/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
for p in "${PATCHES[@]}"; do
	cp "$p" "$W/overlay/patches/"
	basename "$p" >> "$W/overlay/patches/series"
done
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
