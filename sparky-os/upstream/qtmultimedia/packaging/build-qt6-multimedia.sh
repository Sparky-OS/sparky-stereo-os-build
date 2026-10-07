#!/bin/bash
# usage: build-qt6-multimedia.sh [work dir, default /K3D/temp/qtmm-lane/pkg]
# qt6-multimedia 6.11.2-3+stereo3d3: Debian's source with our six patches (qt6-multimedia/*.patch: 0001 the packing in
# QVideoFrameFormat from the previous round, 0002-0004 offerable, 0005-0006 edition only), in a throwaway debian:testing
# container (as the user, 4 threads) with the dependencies of the source and our development repository
set -e
W=${1:-/K3D/temp/qtmm-lane/pkg}
H=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p $W/patches $W/home
cp $H/qt6-multimedia/*.patch $W/patches/
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -e DEBIAN_FRONTEND=noninteractive \
  -v $W:/w -v /K3D/temp/sparky-os/repo:/repo:ro qtmm-build:1 bash -c '
set -e
cd /w
rm -rf tree; mkdir tree; cd tree
apt-get source qt6-multimedia >/dev/null 2>&1
cd qt6-multimedia-6.11.2
cp /w/patches/*.patch debian/patches/
ls /w/patches/*.patch | xargs -n1 basename >> debian/patches/series
# what the patches need beyond Debian'"'"'s build dependencies: the declaration library of the stereo content, and Wayland (the layer)
sed -i "s/^Build-Depends: debhelper-compat (= 13),/Build-Depends: debhelper-compat (= 13),\n               libstereo-declare-dev,\n               libwayland-dev,\n               libx11-dev,\n               qt6-base-private-dev,\n               wayland-protocols,/" debian/control
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 6.11.2-3+stereo3d3 -D UNRELEASED "Keep the chroma and the bits of high bit depth video (4:4:4 and 4:2:2 formats, no hardware decoding that drops bits); VideoOutput takes the views of a stereoscopic 3D video apart (stereoInput, stereoSwapEyes, stereoView, stereoShapeFallback, stereoScaling, stereoSurface); audio sink format and SoX resampler on request. Edition only: the 3D area of a video in a Wayland subsurface declared as full side by side stereo content, and the hi-fi values as the defaults" 2>&1 | tail -1
# the source package first, from the tree as it is before any build
mkdir -p ../srcpkg && cp -a . ../srcpkg/qt6-multimedia-6.11.2 && cp ../qt6-multimedia_6.11.2.orig.tar.xz ../srcpkg/
(cd ../srcpkg/qt6-multimedia-6.11.2 && dpkg-source -b . > ../source.log 2>&1)
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d -B > ../build.log 2>&1 || { tail -40 ../build.log; exit 1; }
tail -4 ../build.log; ls ..
'
