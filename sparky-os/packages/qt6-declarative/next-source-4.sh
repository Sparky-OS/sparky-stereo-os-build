#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-declarative, +stereo3d4 (ORDER 583): the published +stereo3d3+lc1 source
# unpacked, patch s4-0001 appended to its series, libqt6quick6's Depends given the libqt6waylandclient6 whose Wayland
# EGL plugin draws the frame of a framed pair into both eyes (qt6-base +stereo3d23), and the changelog entry of the
# plain version then the Lean Code entry on top of the published history (repo/lc-successor.py --in-place --overlay),
# so the old changelog stays a byte identical suffix. next-source.sh stays the recipe of +stereo3d3.
#   next-source-4.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the published +stereo3d3+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
# Run it twice into two folders: the .dsc and the Debian tarball must hash the same. The date is this folder's last
# commit. The binary packages are built from the new .dsc with release/build-from-lc-dsc.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.11.2+dfsg-3+stereo3d3+lc1' ] || { echo "the published source must be 6.11.2+dfsg-3+stereo3d3+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/qt6-declarative-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
p=s4-0001-Quick-draw-a-framed-window-as-a-pair-where-its-platform-draws-the-frame.patch
grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the published source already has $p" >&2; exit 2; }
cp "$HERE/patches/$p" "$W/overlay/patches/"
echo "$p" >> "$W/overlay/patches/series"
# libqt6quick6 depends on the Wayland client that draws a framed pair's frame into both eyes
python3 - "$W/published/debian/control" "$W/overlay/control" <<'PY'
import sys
text = open(sys.argv[1], encoding='utf-8').read()
old = 'Package: libqt6quick6\nArchitecture: any\nMulti-Arch: same\nPre-Depends: ${misc:Pre-Depends},\nDepends: ${misc:Depends},\n         ${shlibs:Depends},\n'
new = old + '         libqt6waylandclient6 (>= 6.11.2+dfsg-5+stereo3d23~),\n'
if text.count(old) != 1:
    sys.exit("libqt6quick6's Depends is not where this recipe expects it")
open(sys.argv[2], 'w', encoding='utf-8').write(text.replace(old, new))
PY
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d4.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 6.11.2+dfsg-3+stereo3d4 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
