#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# mpv-dmo's next source, made the way every recipe makes its next version (ORDER 311): the published +lc1 source
# unpacked, its plain debian/ directory (repo/plain-from-lc.py) with this folder's new patches appended to the series,
# the libmedia-gpu-route floors raised and the new changelog entry, handed to repo/lc-successor.py --recipe, which adds
# this tree's Lean Code toolkit at NEXT+lc1 next to the same orig tarball.
#   mpv-next-recipe.sh PUBLISHED.dsc NEXT GPU_ROUTE_FLOOR WORK OUT PATCH... -- ITEM...
# NEXT: the plain version (1:0.41.0-dmo9+stereo3d9). GPU_ROUTE_FLOOR: the libmedia-gpu-route version the new patches
# need (0.2.2+lc1). ITEM: the changelog entry's items.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../repo" && pwd)
DSC=$1 NEXT=$2 FLOOR=$3 WORK=$4 OUT=$5
shift 5
patches=()
while [ "$1" != -- ]; do patches+=("$1"); shift; done
shift
# the date of this source is its recipe's: SOURCE_DATE_EPOCH, else the last commit touching the hardware-decode folder (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE/..")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir -p "$WORK" "$OUT"
[ ! -e "$WORK/published" ] || { echo "$WORK/published exists" >&2; exit 1; }
dpkg-source --skip-patches -x "$DSC" "$WORK/published" >/dev/null
python3 "$REPO/plain-from-lc.py" "$WORK/published"
R=$WORK/recipe/debian
mkdir -p "$WORK/recipe"
cp -a "$WORK/published/debian" "$R"
for p in "${patches[@]}"; do
	cp "$p" "$R/patches/"
	basename "$p" >>"$R/patches/series"
done
sed -i "s/libmedia-gpu-route-dev (>= [^)]*)/libmedia-gpu-route-dev (>= $FLOOR)/; s/libmedia-gpu-route0 (>= [^)]*)/libmedia-gpu-route0 (>= $FLOOR)/g" "$R/control"
echo "libmedia-gpu-route floors at $FLOOR: $(grep -o "libmedia-gpu-route[-a-z0-9]* (>= $FLOOR)" "$R/control" | wc -l)"
# the plain entry of the next version, in the form lc-successor.py writes its own
python3 "$HERE/changelog-entry.py" "$R/changelog" "$NEXT" "$@"
python3 "$REPO/lc-successor.py" --recipe "$R" --work "$WORK" "$DSC" "$OUT"
