#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DEBEMAIL=Capitain_Jack@yahoo.com
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS=parallel=4
export DEB_BUILD_PROFILES=pkg.stereo-layer.av
input=${1:?source package directory}
work=${2:?new build directory}
toolkit=${3:?edition toolkit directory}
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$work"
cp "$input/stereo-layer_1.12.0.orig.tar.xz" "$work/"
dpkg-source -x "$input/stereo-layer_1.12.0-1+lc1.dsc" "$work/source"
cd "$work/source"
mkdir -p debian/patches
cp "$recipe/content-inspection.patch" debian/patches/0001-content-inspection.patch
printf '%s\n' 0001-content-inspection.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push
cp "$recipe/debian.control" debian/control
cp "$recipe/debian.rules" debian/rules
rm -rf debian/sparky-lean-toolkit
dch --newversion 1.12.0-3 --distribution unstable 'Keep inspector stereo and projection metadata local to each video track; preserve automatic marked-track preference and explicit selection.'
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare . 1.12.0-3+lc1 --toolkit "$toolkit" \
 --preserve-source 'src/*.h' 'Qt moc and QML type registration consume authored declarations.' \
 --preserve-source 'src/*.cpp' 'Qt moc and QML type registration also scan these sources.'
dpkg-buildpackage -S -us -uc -d
cd "$work"
dpkg-source -x stereo-layer_1.12.0-3+lc1.dsc binary-source
cd binary-source
dpkg-buildpackage -B -us -uc
