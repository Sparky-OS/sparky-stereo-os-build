#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of qt6-base, +stereo3d21 (ORDER 556, two views on Qt's Vulkan path):
# the +stereo3d20+lc1 source (next-source-20.sh; staged by ORDER 554) unpacked, the patch of patches/o556-*.patch
# appended to its series, the manifest of the patches that are ours made again with it, and the changelog entry of
# the plain version then the Lean Code entry on top of that source's history (repo/lc-successor.py --in-place
# --overlay), so the old changelog stays a byte identical suffix.
#   next-source-21.sh PREVIOUS.dsc OUT
#   PREVIOUS.dsc: the +stereo3d20+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
# Run it twice into two folders: the .dsc and the Debian tarball must hash the same. The date is this folder's last commit.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.11.2+dfsg-5+stereo3d20+lc1' ] || { echo "the previous source must be 6.11.2+dfsg-5+stereo3d20+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/qt6-base-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/previous" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/previous/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in "$HERE"/patches/o556-*.patch; do
	name=$(basename "$p")
	if grep -qxF "$name" "$W/previous/debian/patches/series"; then echo "$name is already in the previous series" >&2; exit 2; fi
	cp "$p" "$W/overlay/patches/"
	echo "$name" >> "$W/overlay/patches/series"
done
# the patches that are ours, for the copyright file (repo/provenance-files.py reads each patch's own header):
# the previous source's own, and this version's
[ -e "$W/previous/debian/sparky-provenance-files" ] || { echo "the previous source has no provenance manifest" >&2; exit 2; }
mkdir -p "$W/ours/debian/patches"
cp "$W/previous/debian/patches"/o5*.patch "$W/overlay/patches"/o556-*.patch "$W/ours/debian/patches/"
python3 "$REPO/provenance-files.py" "$W/ours" 'o518-*.patch' 'o554-*.patch' 'o556-*.patch' >/dev/null
# every line of the previous manifest stays
grep -v '^#' "$W/previous/debian/sparky-provenance-files" | while read -r line; do
	grep -qxF "$line" "$W/ours/debian/sparky-provenance-files" || { echo "the new manifest lost $line" >&2; exit 2; }
done
cp "$W/ours/debian/sparky-provenance-files" "$W/overlay/sparky-provenance-files"
mapfile -t items < <(python3 - "$HERE/changelog/stereo3d21.items" <<'PY'
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 6.11.2+dfsg-5+stereo3d21 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
