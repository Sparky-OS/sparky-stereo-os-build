#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of gtk4 after its predecessor: the predecessor unpacked, the step's patches
# appended to its series, any new symbols in libgtk-4-1's list, the changelog entry of the plain version then the Lean
# Code entry on top of that history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte
# identical suffix. The steps:
#   +stereo3d2+lc1 (published; build.sh made it from Debian's 4.24.1+ds-1) to +stereo3d3 (queue row 137, milestone 3):
#     four patches (the size of a stereo area's views, the OpenGL way to an X11 area's window, the format and the color
#     state of the picture, the description of a subsurface's picture on Wayland) and their six symbols;
#   +stereo3d3+lc1 (row 137's) to +stereo3d4 (queue row 147, milestone 3): GtkScrollbar's steppers, no new symbol.
#   next-source.sh PREDECESSOR.dsc OUT
#   PREDECESSOR.dsc: the source the next one is made from (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
case "$(sed -n 's/^Version: //p' "$DSC")" in
	4.24.1+ds-1+stereo3d2+lc1)
		next=4.24.1+ds-1+stereo3d3
		patches=(stereo3d-gtkglarea-stereo-view-size.patch stereo3d-gtkglarea-stereo-x11-gl.patch
			stereo3d-gtkglarea-format-color-state.patch stereo3d-gdk-wayland-subsurface-color-description.patch) ;;
	4.24.1+ds-1+stereo3d3+lc1)
		next=4.24.1+ds-1+stereo3d4
		patches=(stereo3d-gtkscrollbar-steppers.patch) ;;
	*) echo "the source must be 4.24.1+ds-1+stereo3d2+lc1 or 4.24.1+ds-1+stereo3d3+lc1" >&2; exit 2 ;;
esac
W=$(mktemp -d "${TMPDIR:-/tmp}/gtk4-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in "${patches[@]}"; do
	grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the source already has $p" >&2; exit 2; }
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
if [ "$next" = 4.24.1+ds-1+stereo3d3 ]; then
# the patches bring six symbols into libgtk-4-1's list, each in its place (dpkg-gensymbols checks the list)
python3 - "$W/published/debian/libgtk-4-1.symbols.in" "$W/overlay/libgtk-4-1.symbols.in" <<'SYMBOLS'
import sys
from pathlib import Path
s = Path(sys.argv[1]).read_text()
since = '4.24.1+ds-1+stereo3d3'
add = {
    'gtk_gl_area_get_color_state': ' gtk_gl_area_get_context@Base 4.0.0\n',
    'gtk_gl_area_get_format': ' gtk_gl_area_get_has_depth_buffer@Base 4.0.0\n',
    'gtk_gl_area_get_stereo_view_size': ' gtk_gl_area_get_type@Base 4.0.0\n',
    'gtk_gl_area_set_color_state': ' gtk_gl_area_set_error@Base 4.0.0\n',
    'gtk_gl_area_set_format': ' gtk_gl_area_set_has_depth_buffer@Base 4.0.0\n',
    'gtk_gl_area_set_stereo_view_size': ' gtk_gl_area_set_use_es@Base 4.0.0\n',
}
for name, before in add.items():
    assert s.count(before) == 1, before
    assert name + '@' not in s, name
    s = s.replace(before, ' %s@Base %s\n' % (name, since) + before)
Path(sys.argv[2]).write_text(s)
SYMBOLS
fi
mapfile -t items < <(python3 - "$HERE/changelog-${next##*+}.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next "$next" "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
