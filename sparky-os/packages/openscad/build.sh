#!/bin/bash
# Sparky Stereo OS, queue row 50 step 4: openscad 2026.11~rc1-0+stereo3d1+lc1, upstream's tag openscad-2026.11-RC1
# (orig tarball from prepare-source.sh), the packaging of debian/ (Debian's 2021.01-14 packaging as the base, on CMake),
# the patches of patches/ (the stereo 3D view, fitted to the person's depth limits) and the ten-language sentences of
# ../../translations/openscad-3d-view-stereo.po.patch, last in the series.
#   build.sh ORIG_DIR WORK   (disposable container with the build dependencies of debian/control, libstereo-declare-dev
#                            (>= 1.12.2), bubblewrap, clang, nodejs, node-acorn, python3-yaml and devscripts; TREE set)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
ORIG=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
UPSTREAM=2026.11~rc1
VERSION=$UPSTREAM-0+stereo3d1
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
echo "23152b5fb62538911af32f2fe39830854304eecfb82ee2dd63f6ceda1d183c23  $ORIG/openscad_$UPSTREAM.orig.tar.xz" | sha256sum -c --quiet
cp "$ORIG/openscad_$UPSTREAM.orig.tar.xz" "$WORK/"
cd "$WORK"; tar -xJf "openscad_$UPSTREAM.orig.tar.xz"; cd "openscad-$UPSTREAM"
cp -a "$HERE/debian" debian
mkdir -p debian/patches
for p in "$HERE"/patches/*.patch "$TREE/translations/openscad-3d-view-stereo.po.patch"; do
	cp "$p" debian/patches/; basename "$p" >> debian/patches/series
done
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then
		dch --create --package openscad --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"
	else
		dch --date "$DATE" -a "$item"
	fi
	n=$((n + 1))
done < "$HERE/changelog/openscad.items"
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
# The debug information is kept, compressed in the objects and the linked files (most of a CGAL build's tree is debug
# information); dh_strip moves it into openscad-dbgsym as before, and the installed files are the same files.
export DEB_CFLAGS_MAINT_APPEND='-gz=zstd' DEB_CXXFLAGS_MAINT_APPEND='-gz=zstd'
export DEB_LDFLAGS_MAINT_APPEND='-Wl,--compress-debug-sections=zstd'
dpkg-buildpackage -us -uc -sa -j4
