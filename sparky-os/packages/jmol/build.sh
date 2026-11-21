#!/bin/bash
# Sparky Stereo OS, ORDER 50 steps 4 and 5: jmol 16.3.55+dfsg-1+stereo3d2+lc1, Debian testing's own source plus patches/ (Jmol's
# display as a declared 3D area, Enable 3D, the preset). All three binary packages are Architecture: all
# (--build=source,all).
#   build.sh DEBIAN.dsc WORK   (disposable container with jmol's build dependencies, bubblewrap, clang, python3,
#                               devscripts; TREE mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '16.3.55+dfsg-1' ] || { echo "jmol: this recipe is for Debian's 16.3.55+dfsg-1" >&2; exit 2; }
D=$(dirname "$DSC")
cp "$D"/jmol_16.3.55+dfsg-1.debian.tar.xz "$D"/jmol_16.3.55+dfsg.orig.tar.xz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd jmol-16.3.55+dfsg
for p in "$HERE"/patches/*.patch; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
python3 - <<'PY'
from pathlib import Path
c = Path('debian/control').read_text()
old = 'Package: libjmol-java\nArchitecture: all\nSection: java\nDepends: ${java:Depends},\n'
assert c.count(old) == 1, 'Debian control changed'
# the jar loads both libraries through JNA when the display becomes a 3D area (Stereo3D.java); shlibs cannot see that
Path('debian/control').write_text(c.replace(old, old + '         libstereo-declare1 (>= 1.7.0),\n         libx11-6,\n', 1))
PY
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
# one changelog entry per edition version: +stereo3d1 (jmol.items), +stereo3d2 (jmol-stereo3d2.items)
for entry in 1:jmol.items 2:jmol-stereo3d2.items; do
	VERSION=16.3.55+dfsg-1+stereo3d${entry%%:*}
	n=0
	while IFS= read -r item; do
		[ -n "$item" ] || continue
		if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
		n=$((n + 1))
	done < "$HERE/changelog/${entry#*:}"
done
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
dpkg-buildpackage -us -uc -sa -j4 --build=source,all
