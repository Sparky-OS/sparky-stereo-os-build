#!/bin/bash
# Sparky Stereo OS, ORDER 50 step 5: vtk9 9.6.2+ds-3+stereo3d1+lc1, Debian testing's own source plus patches/ (VTK's Qt
# windows set the draw buffer of their blit through vtkOpenGLState, so a quad-buffered window's right eye no longer leaves
# the state cache stale). The source and the architecture-dependent packages are built (--build=source,any): vtk9-doc and
# vtk9-examples are Debian's, unchanged.
#   build.sh DEBIAN.dsc WORK   (disposable container with vtk9's build dependencies, bubblewrap, clang, nodejs, node-acorn,
#                               python3-yaml, devscripts; TREE mounted; SPARKY_LC_* as the build record route needs them)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '9.6.2+ds-3' ] || { echo "vtk9: this recipe is for Debian's 9.6.2+ds-3" >&2; exit 2; }
echo "bf058bab526adac5ab0a475e44943cfccd8a5aea17b929213331a9a4693b9b74  $DSC" | sha256sum -c --quiet
D=$(dirname "$DSC")
cp "$D"/vtk9_9.6.2+ds-3.debian.tar.xz "$D"/vtk9_9.6.2+ds.orig.tar.xz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd vtk9-9.6.2+ds
for p in "$HERE"/patches/*.patch; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
VERSION=9.6.2+ds-3+stereo3d1
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
	n=$((n + 1))
done < "$HERE/changelog/vtk9.items"
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
# The debug information is kept, compressed in the objects and the linked files (Debian's own amd64 build of 9.6.2+ds-3
# needed 32.5 GB, most of it debug information); dh_strip moves it into the -dbgsym packages compressed as before, and the
# installed files are the same files (KiCad's recipe does the same).
export DEB_CFLAGS_MAINT_APPEND='-gz=zstd' DEB_CXXFLAGS_MAINT_APPEND='-gz=zstd'
export DEB_LDFLAGS_MAINT_APPEND='-Wl,--compress-debug-sections=zstd'
dpkg-buildpackage -us -uc -sa -j4 --build=source,any
