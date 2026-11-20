#!/bin/bash
# Sparky Stereo OS, ORDER 50 step 3: grass 8.5.0-1+stereo3d1+lc1, Debian testing's own source plus the five patches of
# patches/ (the 3D view's stereo pair, fitted to the person's depth limits) and the ten-language sentences of
# ../../translations/grass-3d-view-stereo.po.patch.
#   build.sh DEBIAN.dsc WORK   (disposable container with the build dependencies, bubblewrap, clang, python3, devscripts;
#                               TREE mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '8.5.0-1' ] || { echo "grass: this recipe is for Debian's 8.5.0-1" >&2; exit 2; }
D=$(dirname "$DSC")
cp "$D"/grass_8.5.0-1.debian.tar.xz "$D"/grass_8.5.0.orig.tar.gz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd grass-8.5.0
for p in "$HERE"/patches/*.patch "$TREE/translations/grass-3d-view-stereo.po.patch"; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
# the GUI calls the new ogsf functions of grass-core and loads libstereo-declare at run time
python3 - <<'PY'
from pathlib import Path
c = Path('debian/control').read_text()
old = 'Package: grass-gui\nArchitecture: any\nDepends: grass-core,\n'
assert c.count(old) == 1, 'Debian control changed'
c = c.replace(old, 'Package: grass-gui\nArchitecture: any\nDepends: grass-core (= ${binary:Version}),\n         libstereo-declare1 (>= 1.11.0),\n', 1)
Path('debian/control').write_text(c)
PY
VERSION=8.5.0-1+stereo3d1
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
	n=$((n + 1))
done < "$HERE/changelog/grass.items"
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
dpkg-buildpackage -us -uc -sa -j4
