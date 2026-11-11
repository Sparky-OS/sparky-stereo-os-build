#!/bin/bash
# build the stereo qt6-multimedia in a clean tree: Debian's source + our patch
set -e
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
cd /w/build/qt
rm -rf tree; mkdir tree; cd tree
apt-get source qt6-multimedia >/dev/null 2>&1
cd qt6-multimedia-6.11.2
cp /w/src/0001-qtmultimedia-stereo-mode.diff debian/patches/0001-Add-StereoMode-to-QVideoFrameFormat-and-fill-it-from-FFmpeg.patch
echo 0001-Add-StereoMode-to-QVideoFrameFormat-and-fill-it-from-FFmpeg.patch >> debian/patches/series
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch --date "$SOURCE_DATE_RFC2822" -v 6.11.2-3+stereo3d2 -D UNRELEASED "Add QVideoFrameFormat::stereoMode(), stereoFlags() and stereoView() for every frame packing of H.264 Table D-8 and Matroska StereoMode, filled by the FFmpeg backend" 2>&1 | tail -1
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d 2>&1 | tail -5
