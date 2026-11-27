#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: next-source-26.sh PREVIOUS_25.dsc OUT
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../repo" && pwd)
dsc=$(realpath "$1")
out=$(realpath -m "$2")
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$repo/reproducible.py" epoch "$here")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$dsc")" = '6.11.2+dfsg-5+stereo3d25+lc1' ]
mkdir -p "$(dirname "$out")"
work=$(mktemp -d "$(dirname "$out")/qt6-base-source-XXXXXX")
trap 'rm -rf "$work"' EXIT
dpkg-source --no-copy --skip-patches -x "$dsc" "$work/previous" >/dev/null
mkdir -p "$work/overlay/patches"
python3 - "$work" <<'PY'
from pathlib import Path
import sys

work = Path(sys.argv[1])
previous = work / "previous/debian"
overlay = work / "overlay"
patches = ("o121b-0001.patch", "o121b-0002.patch")
for name, prefix in (("patches/series", ""), ("sparky-provenance-files", "debian/patches/")):
    text = (previous / name).read_text()
    entries = [prefix + patch for patch in patches]
    assert all(entry not in text.splitlines() for entry in entries)
    (overlay / name).write_text(text.rstrip("\n") + "\n" + "\n".join(entries) + "\n")

text = (previous / "control").read_text()
prefix, stanza = text.split("\nPackage: libqt6waylandclient6\n", 1)
stanza, suffix = stanza.split("\nPackage: ", 1)
old = "        kwin-wayland (<< 4:6.7.4-2+stereo3d23~),"
assert stanza.count(old) == 1
new = """        kwin-wayland (<< 4:6.7.4-2+stereo3d70~),
        libkwin6 (<< 4:6.7.4-2+stereo3d70~),"""
(overlay / "control").write_text(prefix + "\nPackage: libqt6waylandclient6\n" + stanza.replace(old, new) + "\nPackage: " + suffix)
PY
cp "$here/patches/o121b-0001.patch" "$here/patches/o121b-0002.patch" "$work/overlay/patches/"
python3 "$repo/lc-successor.py" --in-place --next 6.11.2+dfsg-5+stereo3d26 --overlay "$work/overlay" --work "$work" \
    --item 'Paint declared rectangles with both element steps and the surface output width from the same Wayland event group (row 121).' \
    --item 'Draw the source of a widget graphics effect per eye when the widget declares rectangles, preserving the effect.' \
    --item 'Break older KWin versions that cannot send the two-step event.' \
    "$dsc" "$out"
name=qt6-base_6.11.2+dfsg.orig.tar.xz
if [ ! -e "$out/$name" ]; then
    cp "$(dirname "$dsc")/$name" "$out/"
fi
