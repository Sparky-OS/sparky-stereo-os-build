#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 17: the next +lc1 source of kio-extras, whose thumbnail of a 3MF file shows the slicer picture, or the model as a stereo pair, and
# the person may prefer the render, after the way of ../thumbnails-576/next-source.sh: the published +lc1 source
# unpacked; this folder's patch appended to its series; and the plain entry, then the Lean Code entry, on top of the published
# history (repo/lc-successor.py --in-place --overlay), so the old changelog stays a byte identical suffix of the new one.
#   next-source.sh PUBLISHED.dsc OUT
# Run it where dpkg-source is (the Lean Code migration container; round.sh does).
set -euo pipefail
# A new Debian upstream release retains this producer and its complete patch set.
if [[ ${1:-} == --debian-successor ]]; then
    shift
    [[ $# == 3 ]] || { echo "Usage: $0 --debian-successor DEBIAN-INPUTS PUBLISHED-INPUTS WORK" >&2; exit 2; }
    here=$(cd "$(dirname "$0")" && pwd)
    exec python3 "$here/../../release/prepare-frameworks-successor.py" "$here/successor-26.08/successor.json" "$@"
fi
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching this folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
PUBLISHED_VERSION=$(sed -n 's/^Version: //p' "$DSC")
[ "${PUBLISHED_VERSION#*:}" = '26.04.0-1+stereo3d6+lc1' ] || { echo "kio-extras: the successor is made from +stereo3d6+lc1, not $PUBLISHED_VERSION" >&2; exit 2; }
NEXT=4:26.04.0-1+stereo3d7
W=$(mktemp -d "${TMPDIR:-/tmp}/kio-extras-3mf-17-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ "$(tail -c1 "$W/overlay/patches/series" | od -An -tx1 | tr -d ' ')" = 0a ] || echo >> "$W/overlay/patches/series"
cp "$HERE/patches/kio-extras-3mf-thumbnail.patch" "$W/overlay/patches/"
echo kio-extras-3mf-thumbnail.patch >> "$W/overlay/patches/series"
mapfile -t items < <(python3 - "$HERE/changelog/kio-extras.items" <<'PY'
import sys
# one item per paragraph (blank line between), its lines joined by a space
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next "$NEXT" "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
