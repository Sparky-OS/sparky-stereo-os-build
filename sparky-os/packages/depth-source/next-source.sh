#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-multimedia or dragon with the depth-as-a-3D-source patches (ORDER 151,
# step R part 2, group 2). The published +lc1 source unpacked; this folder's patches appended to its series; the
# dependency texts the new version changes; and the changelog entry of the plain version, then the Lean Code entry,
# on top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte
# identical suffix of the new one (the dch trap of ORDER 278 is never met: dch is not used).
#   next-source.sh PACKAGE PUBLISHED.dsc OUT [SYMBOLS_ADD]
#   PACKAGE: qt6-multimedia | dragon | plank-player
#   PUBLISHED.dsc: the published +lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
#   SYMBOLS_ADD (qt6-multimedia): a file of symbol lines for debian/libqt6multimedia6.symbols (none for the successor of +stereo3d14, whose symbols are published)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
PKG=$1 DSC=$(readlink -f "$2") OUT=$3 SYM=${4:-}
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
PUBLISHED_VERSION=$(sed -n 's/^Version: //p' "$DSC")
ITEMS=$HERE/changelog/$PKG.items
case $PKG in
qt6-multimedia)
	# a successor of the published +stereo3d14+lc1 (ORDER 448): its series already holds the patches before 0046, its control and symbols are +14's
	if [ "$PUBLISHED_VERSION" = '6.11.2-3+stereo3d14+lc1' ]; then
		NEXT=6.11.2-3+stereo3d15
		depends=()
		ITEMS=$HERE/changelog/qt6-multimedia-stereo3d15.items
		[ -z "$SYM" ] || { echo "the +stereo3d14 symbols are in the published source: no SYMBOLS_ADD" >&2; exit 2; }
	else
	NEXT=6.11.2-3+stereo3d14
	depends=(--depends $'               libstereo-policy-dev (>= 1.5.0),' $'               libstereo-dibr-dev (>= 1.17.1),\n               libstereo-policy-dev (>= 1.5.0),'
		--depends 'libavcodec63 (>= 10:9.0.2-dmo1+stereo3d6+lc1), libpipewire-0.3-0t64 [linux-any],' 'libavcodec63 (>= 10:9.0.2-dmo1+stereo3d6+lc1), libavutil61 (>= 10:9.0.2-dmo1+stereo3d5~), libpipewire-0.3-0t64 [linux-any],'
		--depends $'Depends: ${misc:Depends},\n         ${qml6:Depends},\n         ${shlibs:Depends},\nBreaks: libqt6multimediaquick6,' $'Depends: ${misc:Depends},\n         ${qml6:Depends},\n         ${shlibs:Depends},\n         libgbm1,\n         libwayland-egl1,\nBreaks: libqt6multimediaquick6,')
	fi
	;;
dragon)
	if [ "$PUBLISHED_VERSION" = '4:26.04.0-1+stereo3d10+lc1' ] || [ "$PUBLISHED_VERSION" = '26.04.0-1+stereo3d10+lc1' ]; then
		NEXT=4:26.04.0-1+stereo3d11
		ITEMS=$HERE/changelog/dragon-stereo3d11.items
		depends=()
	else
	# a successor of the published +stereo3d9+lc1 (ORDER 453): its series holds 0001 to 0008 and the translations; it needs the Qt Multimedia that says a refused declaration (+stereo3d15, stereoLayerFailure)
	if [ "$PUBLISHED_VERSION" = '4:26.04.0-1+stereo3d9+lc1' ] || [ "$PUBLISHED_VERSION" = '26.04.0-1+stereo3d9+lc1' ]; then
		NEXT=4:26.04.0-1+stereo3d11
		ITEMS=$HERE/changelog/dragon-stereo3d11.items
		depends=(--depends 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1),' 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d15+lc1),'
			--depends 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d14+lc1),' 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d15+lc1),'
			--depends 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d14+lc1),' 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d15+lc1),')
	else
	NEXT=4:26.04.0-1+stereo3d9
	depends=(--depends 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d10+lc1),' 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1),'
		--depends 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d10+lc1),' 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d14+lc1),'
		--depends 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d10+lc1),' 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d14+lc1),'
		--depends $'         ${misc:Depends},' $'         kde-cli-tools,\n         kscreen,\n         libstereo-layer1 (>= 1.17.1),\n         mkvtoolnix,\n         ${misc:Depends},'
		--depends 'libkf6windowsystem-dev (>= 6.12.0~),' $'libkf6windowsystem-dev (>= 6.12.0~),\n               libstereo-av-dev (>= 1.17.1),\n               libstereo-policy-dev (>= 1.17.1),'
		--depends 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1),' $'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1), ffmpeg <!nocheck>, mkvtoolnix <!nocheck>,')
	fi
	fi
	;;
plank-player)
	if [ "$PUBLISHED_VERSION" = '5.27.80+git20261005.f87e775-1+stereo3d3+lc1' ]; then
		NEXT=5.27.80+git20261005.f87e775-1+stereo3d4
		ITEMS=$HERE/changelog/plank-player-stereo3d4.items
		depends=(--depends '         qml6-module-org-kde-bigscreen,' $'         qml6-module-org-kde-desktop,\n         qml6-module-org-kde-bigscreen,'
			--depends $'Recommends: qml6-module-org-kde-desktop\n' '')
	else
	# a successor of the published 5.27.80+git20261005.f87e775-1+stereo3d2+lc1 (ORDER 453b): the orig tarball is the published one, patch 0003 shows a refused declaration (needs Qt Multimedia +stereo3d15)
	[ "$PUBLISHED_VERSION" = '5.27.80+git20261005.f87e775-1+stereo3d2+lc1' ] || { echo "plank-player: the successor is made from +stereo3d2+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
	NEXT=5.27.80+git20261005.f87e775-1+stereo3d4
	ITEMS=$HERE/changelog/plank-player-stereo3d4.items
	depends=(--depends 'libqt6multimedia6 (>= 6.11.2-3+stereo3d3~),' 'libqt6multimedia6 (>= 6.11.2-3+stereo3d15~),'
		--depends 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d3~),' 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d15~),'
		--depends '         qml6-module-org-kde-bigscreen,' $'         qml6-module-org-kde-desktop,\n         qml6-module-org-kde-bigscreen,'
		--depends $'Recommends: qml6-module-org-kde-desktop\n' '')
	fi
	;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/depth-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | xxd -p)" = 0a ] || echo >> "$W/overlay/patches/series"
# the patches the published series does not hold yet (a successor of +stereo3d14 adds 0046 only)
PATCHDIR=$HERE/patches/$PKG
[ "$PKG" != plank-player ] || PATCHDIR=$HERE/../../upstream/qtmultimedia/plank-player
for p in "$PATCHDIR"/*.patch; do
	case "$PKG:$NEXT:$(basename "$p")" in
		dragon:*+stereo3d9:0009-*|dragon:*+stereo3d9:001[0-2]-*) continue ;;
	esac
	grep -qxF "$(basename "$p")" "$W/published/debian/patches/series" && continue
	cp "$p" "$W/overlay/patches/"
	basename "$p" >> "$W/overlay/patches/series"
done
if [ -n "$SYM" ]; then
	cp "$W/published/debian/libqt6multimedia6.symbols" "$W/overlay/libqt6multimedia6.symbols"
	cat "$SYM" >> "$W/overlay/libqt6multimedia6.symbols"
fi
# The vendored ffnvcodec header of patch 0032 (Qt dev 2506a582c8, MIT) gets its entry in debian/copyright (Opus, ORDER 411 2h review).
if [ "$PKG" = qt6-multimedia ] && [ "$PUBLISHED_VERSION" != 6.11.2-3+stereo3d14+lc1 ] && [ -f "$HERE/patches/$PKG/0032-3rdparty-import-ffnvcodec-dynlink_cuda.h.patch" ]; then
	cp "$W/published/debian/copyright" "$W/overlay/copyright"
	grep -q '^Files: src/3rdparty/nv-codec-headers/' "$W/overlay/copyright" || cat >> "$W/overlay/copyright" <<'COPYRIGHT'

Files: src/3rdparty/nv-codec-headers/*
Copyright: 2016, no holder named in ffnvcodec/dynlink_cuda.h (FFmpeg's nv-codec-headers, carried by Qt)
License: Expat

License: Expat
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the software, and to permit persons to whom the
 software is furnished to do so, subject to the following
 conditions:
 .
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 .
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
COPYRIGHT
fi
mapfile -t items < <(python3 - "$ITEMS" <<'PY'
import sys
# one item per paragraph (blank line between), its lines joined by a space
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next "$NEXT" "${args[@]}" "${depends[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
