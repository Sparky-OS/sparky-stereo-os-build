#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
export DEBEMAIL=Capitain_Jack@yahoo.com
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS=parallel=4
unset DEB_BUILD_PROFILES # Build the complete published shared-library cohort.
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
cp "$recipe/native-input.patch" debian/patches/0002-native-input.patch
printf '%s\n' 0002-native-input.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push
cp "$recipe/debian.control" debian/control
cp "$recipe/debian.rules" debian/rules
rm -rf debian/sparky-lean-toolkit
dch --date "$SOURCE_DATE_RFC2822" --newversion 1.12.0-4 --distribution unstable 'Expose the existing anaglyph reconstruction for native video consumers without RGB32 precision loss; keep codec declarations coherent when replacing container anaglyph marks.'
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare . 1.12.0-4+lc1 --toolkit "$toolkit" \
 --preserve-source 'src/*.h' 'Qt moc and QML type registration consume authored declarations.' \
 --preserve-source 'src/*.cpp' 'Qt moc and QML type registration also scan these sources.'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -S -us -uc -d
cd "$work"
dpkg-source -x stereo-layer_1.12.0-4+lc1.dsc binary-source
cd binary-source
dpkg-buildpackage -B -us -uc
