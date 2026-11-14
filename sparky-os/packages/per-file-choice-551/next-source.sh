#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 551: the next +lc1 source of dolphin, ffmpegthumbs, gwenview or kio-extras with the per-file 3D choice
# (the stereo layer's shared menu and store), after the way of ../depth-source/next-source.sh: the published +lc1 source
# unpacked; this folder's patches appended to its series; the dependency texts and the rules line the new version
# changes; and the plain entry, then the Lean Code entry, on top of the published history (repo/lc-successor.py
# --in-place --overlay), so the old changelog stays a byte identical suffix of the new one.
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
# Every one of the three is built against the layer that holds the store and the menu, and stops when it is older:
# without the version in Build-Depends and CMake's own switch in the rules, an older libstereo-layer-dev is "not found",
# CMake prints no error and the program is built without stereo (ORDER 512 found it).
REQUIRE='-DCMAKE_REQUIRE_FIND_PACKAGE_StereoLayer=ON'
rules=()
case $PKG in
dolphin)
	[ "${PUBLISHED_VERSION#*:}" = '26.08.0-1+stereo3d6+lc1' ] || { echo "dolphin: the successor is made from +stereo3d6+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:26.08.0-1+stereo3d7
	PATCHES=(dolphin-per-file-stereo-choice.patch)
	depends=(--depends 'Build-Depends: libstereo-layer-dev (>= 1.4.0),' 'Build-Depends: libstereo-layer-dev (>= 1.18.0),')
	rules=('	dh_auto_configure -Skf6 -- -DBUILD_TESTING=OFF' "	dh_auto_configure -Skf6 -- -DBUILD_TESTING=OFF $REQUIRE")
	;;
ffmpegthumbs)
	[ "${PUBLISHED_VERSION#*:}" = '26.04.0-1+stereo3d4+lc1' ] || { echo "ffmpegthumbs: the successor is made from +stereo3d4+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:26.04.0-1+stereo3d5
	PATCHES=(ffmpegthumbs-per-file-stereo-choice.patch)
	depends=(--depends 'Build-Depends: libstereo-layer-dev (>= 1.5.0),' 'Build-Depends: libstereo-layer-dev (>= 1.18.0),')
	rules=($'%:\n\tdh $@\n' $'%:\n\tdh $@\n\noverride_dh_auto_configure:\n\tdh_auto_configure -- '"$REQUIRE"$'\n')
	;;
kio-extras)
	# +stereo3d5 (ORDER 504: the thumbnailers' versions go up) was staged and never published, with a changelog Lintian could not
	# parse; this is the same patch on the published +stereo3d4, built against the layer that holds the per-file store
	[ "${PUBLISHED_VERSION#*:}" = '26.04.0-1+stereo3d4+lc1' ] || { echo "kio-extras: the successor is made from +stereo3d4+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:26.04.0-1+stereo3d5
	PATCHES=(../viewers-504/patches/kio-extras-thumbnailer-versions.patch)
	depends=(--depends 'Build-Depends: libstereo-layer-dev (>= 1.5.1),' 'Build-Depends: libstereo-layer-dev (>= 1.18.0),'
		--depends '         libstereo-layer1 (>= 1.5.1),' '         libstereo-layer1 (>= 1.18.0),')
	rules=('	dh_auto_configure -Skf6 -- -DBUILD_TESTING=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5' "	dh_auto_configure -Skf6 -- -DBUILD_TESTING=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 $REQUIRE")
	;;
gwenview)
	# +stereo3d9 (ORDER 504: the picture area's opaque background) was staged and never published; +stereo3d10 carries its patch too
	[ "${PUBLISHED_VERSION#*:}" = '26.04.0-1+stereo3d8+lc1' ] || { echo "gwenview: the successor is made from +stereo3d8+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=4:26.04.0-1+stereo3d10
	PATCHES=(../viewers-504/patches/stereo-opaque-picture-background.patch gwenview-shared-per-file-choice.patch)
	depends=(--depends 'libstereo-layer-dev (>= 1.11.0-1+lc1),' 'libstereo-layer-dev (>= 1.18.0),')
	;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/per-file-choice-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
for p in "${PATCHES[@]}"; do
	case $p in ../*) file=$HERE/$p ;; *) file=$HERE/patches/$p ;; esac
	cp "$file" "$W/overlay/patches/"
	basename "$p" >> "$W/overlay/patches/series"
done
if [ ${#rules[@]} -gt 0 ]; then
	python3 - "$W/published/debian/rules" "$W/overlay/rules" "${rules[0]}" "${rules[1]}" <<'PY'
import sys
source, target, old, new = sys.argv[1:5]
text = open(source, encoding='utf-8').read()
# the line is changed exactly once, or the recipe stops: a rules file that moved is read by a person first
if text.count(old) != 1:
    sys.exit(f'{source}: {old!r} is there {text.count(old)} times, not once')
open(target, 'w', encoding='utf-8').write(text.replace(old, new))
PY
	chmod --reference="$W/published/debian/rules" "$W/overlay/rules"
fi
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
