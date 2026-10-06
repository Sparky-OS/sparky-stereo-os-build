#!/bin/bash
# build the stereo mlt: Debian's source + our three patches (inside the kd build image, as the user)
set -e
cd /w/build/mlt
rm -rf tree; mkdir tree; cd tree
apt-get source mlt >/dev/null 2>&1
cd mlt-7.40.0
cat debian/source/format
mkdir -p debian/patches
cp /w/src/mlt-patches/*.patch debian/patches/
ls debian/patches/*.patch | xargs -n1 basename > debian/patches/series
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 7.40.0-1+stereo3d1 -D UNRELEASED "Tell the stereoscopic 3D packing of a video (meta.media.stereo3d.type and .invert on the producer) and write it (stereo3d and stereo3d_invert on the avformat consumer: the frame packing arrangement SEI and Matroska's StereoMode); build the consumer against FFmpeg 8 and later" 2>&1 | tail -1
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d 2>&1 | tail -5
