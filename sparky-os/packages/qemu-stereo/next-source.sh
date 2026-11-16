#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qemu, +stereo3d8 (ORDER 156b): the published +stereo3d7+lc1 source unpacked,
# patches stereo3d/0012 to 0021 appended to its series (Sparky-OS/qemu order156-depth over +stereo3d7: the five commits the
# depth work stands on, then the depth work), libstereo-dibr-dev added to the build dependencies of debian/control and of
# the debian/control-in template it is regenerated from, and the changelog entry of the plain version then the Lean Code
# entry on top of the published history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte
# identical suffix. add-refresh-patches.py stays the +stereo3d7 recipe (it starts from the +stereo3d6 source).
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the 1:11.1.2+ds-3+stereo3d7+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '1:11.1.2+ds-3+stereo3d7+lc1' ] || { echo "the source must be 1:11.1.2+ds-3+stereo3d7+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/qemu-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches/stereo3d"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0012-ui-retain-non-rectangular-stereo-metadata.patch \
	0013-ui-copy-native-line-samples.patch \
	0014-gtk-select-native-line-views.patch \
	0015-rutabaga-clear-stereo-before-disable.patch \
	0016-gtk-bound-stereo-gl-readback.patch \
	0017-virtio-gpu-read-graphics-rectangles.patch \
	0018-edid-declare-l-depth.patch \
	0019-gtk-draw-picture-with-depth.patch \
	0020-stereo-depth-graphics-depth-zero-comment.patch \
	0021-wayland-stereo-say-declaration-refused.patch; do
	grep -qxF "stereo3d/$p" "$W/published/debian/patches/series" && { echo "the source already has $p" >&2; exit 2; }
	cp "$HERE/patches/$p" "$W/overlay/patches/stereo3d/"
	echo "stereo3d/$p" >> "$W/overlay/patches/series"
done
# the GTK display draws a guest's picture with its depth through libstereo-dibr (patch 0019); control.mk regenerates
# debian/control from control-in at clean, so both carry it, next to libstereo-declare-dev
python3 - "$W/published/debian" "$W/overlay" <<'PY'
import sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
old = 'libstereo-declare-dev (>= 1.3.0) [amd64], '
new = old + 'libstereo-dibr-dev (>= 1.17.1) [amd64], '
for name in ('control', 'control-in'):
    text = (src / name).read_text()
    if text.count(old) != 1 or 'libstereo-dibr-dev' in text:
        raise SystemExit(f'review debian/{name}: expected one {old.strip()} and no libstereo-dibr-dev')
    (dst / name).write_text(text.replace(old, new))
PY
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d8.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1].split('\n\n -- ', 1)[0]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 1:11.1.2+ds-3+stereo3d8 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
