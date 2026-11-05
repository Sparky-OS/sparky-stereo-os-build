#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-multimedia or dragon with the depth-as-a-3D-source patches (ORDER 151,
# step R part 2, group 2). The published +lc1 source unpacked; this folder's patches appended to its series; the
# dependency texts the new version changes; and the changelog entry of the plain version, then the Lean Code entry,
# on top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte
# identical suffix of the new one (the dch trap of ORDER 278 is never met: dch is not used).
#   next-source.sh PACKAGE PUBLISHED.dsc OUT [SYMBOLS_ADD]
#   PACKAGE: qt6-multimedia | dragon
#   PUBLISHED.dsc: the published +lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
#   SYMBOLS_ADD (qt6-multimedia): a file of symbol lines for debian/libqt6multimedia6.symbols
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
PKG=$1 DSC=$(readlink -f "$2") OUT=$3 SYM=${4:-}
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
case $PKG in
qt6-multimedia)
	NEXT=6.11.2-3+stereo3d14
	depends=(--depends $'               libstereo-policy-dev (>= 1.5.0),' $'               libstereo-dibr-dev (>= 1.17.1),\n               libstereo-policy-dev (>= 1.5.0),'
		--depends 'libavcodec63 (>= 10:9.0.2-dmo1+stereo3d6+lc1), libpipewire-0.3-0t64 [linux-any],' 'libavcodec63 (>= 10:9.0.2-dmo1+stereo3d6+lc1), libavutil61 (>= 10:9.0.2-dmo1+stereo3d5~), libpipewire-0.3-0t64 [linux-any],')
	;;
dragon)
	NEXT=4:26.04.0-1+stereo3d9
	depends=(--depends 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d10+lc1),' 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1),'
		--depends 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d10+lc1),' 'Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d14+lc1),'
		--depends 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d10+lc1),' 'qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d14+lc1),'
		--depends $'         ${misc:Depends},' $'         kde-cli-tools,\n         kscreen,\n         libstereo-layer1 (>= 1.17.1),\n         mkvtoolnix,\n         ${misc:Depends},'
		--depends 'libkf6windowsystem-dev (>= 6.12.0~),' $'libkf6windowsystem-dev (>= 6.12.0~),\n               libstereo-av-dev (>= 1.17.1),\n               libstereo-policy-dev (>= 1.17.1),'
		--depends 'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1),' $'qt6-multimedia-dev (>= 6.11.2-3+stereo3d14+lc1), ffmpeg <!nocheck>, mkvtoolnix <!nocheck>,')
	;;
*) echo "unknown package $PKG" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/depth-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$HERE/patches/$PKG"/*.patch "$W/overlay/patches/"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | xxd -p)" = 0a ] || echo >> "$W/overlay/patches/series"
for p in "$HERE/patches/$PKG"/*.patch; do basename "$p" >> "$W/overlay/patches/series"; done
if [ -n "$SYM" ]; then
	cp "$W/published/debian/libqt6multimedia6.symbols" "$W/overlay/libqt6multimedia6.symbols"
	cat "$SYM" >> "$W/overlay/libqt6multimedia6.symbols"
fi
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
