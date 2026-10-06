#!/bin/bash
# build the stereo qt6-multimedia in a clean tree: Debian's source + our patch
set -e
cd /w/build/qt
rm -rf tree; mkdir tree; cd tree
apt-get source qt6-multimedia >/dev/null 2>&1
cd qt6-multimedia-6.11.2
cp /w/src/0001-qtmultimedia-stereo-mode.diff debian/patches/0001-Add-StereoMode-to-QVideoFrameFormat-and-fill-it-from-FFmpeg.patch
echo 0001-Add-StereoMode-to-QVideoFrameFormat-and-fill-it-from-FFmpeg.patch >> debian/patches/series
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 6.11.2-3+stereo3d1 -D UNRELEASED "Add QVideoFrameFormat::stereoMode(), filled by the FFmpeg backend from the frame's Stereo 3D side data (the frame packing SEI and Matroska's StereoMode)" 2>&1 | tail -1
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d 2>&1 | tail -5
