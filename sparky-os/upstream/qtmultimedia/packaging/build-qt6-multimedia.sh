#!/bin/bash
# usage: build-qt6-multimedia.sh [work dir, default ${SPARKY_SCRATCH}/qtmm-lane/pkg]
# qt6-multimedia 6.11.2-3+stereo3d4: Debian's source with our eight patches (qt6-multimedia/*.patch: 0001 the packing in
# QVideoFrameFormat from the previous round, 0002-0004 and 0007 offerable, 0005, 0006 and 0008 edition only), in a throwaway debian:testing
# container (as the user, 4 threads) with the dependencies of the source and our development repository
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -e
W=${1:-${SPARKY_SCRATCH:?}/qtmm-lane/pkg}
H=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p $W/patches $W/home
cp $H/qt6-multimedia/*.patch $W/patches/
# dpkg-source cannot take a git binary diff: the test clip of 0007 stays in the git branches, and the
# series of the package gets the patch without it (the package does not build the tests)
python3 - $W/patches <<'PY'
import sys, glob, re
for f in glob.glob(sys.argv[1] + '/*.patch'):
    t = open(f).read()
    u = re.sub(r'diff --git [^\n]*\.mp4 [^\n]*\n(?:(?!diff --git ).*\n)*', '', t)
    if u != t:
        open(f, 'w').write(u)
PY
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -e DEBIAN_FRONTEND=noninteractive \
  -v $W:/w -v ${SPARKY_REPO_DIR:?}:/repo:ro qtmm-build:1 bash -c '
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
dch -v 6.11.2-3+stereo3d4 -D UNRELEASED "Keep the chroma and the bits of high bit depth video (4:4:4 and 4:2:2 formats, no hardware decoding that drops bits); VideoOutput takes the views of a stereoscopic 3D video apart (stereoInput, stereoSwapEyes, stereoView, stereoShapeFallback, stereoScaling, stereoSurface); audio sink format and SoX resampler on request; report the mastering display peak luminance in nits (was 10^4 times too high). Edition only: the 3D area of a video in a Wayland subsurface declared as full side by side stereo content, the hi-fi values and the shape fallback as the defaults, and the views of an anamorphic 3D video restored from the stored samples" 2>&1 | tail -1
# the source package first, from the tree as it is before any build
mkdir -p ../srcpkg && cp -a . ../srcpkg/qt6-multimedia-6.11.2 && cp ../qt6-multimedia_6.11.2.orig.tar.xz ../srcpkg/
(cd ../srcpkg/qt6-multimedia-6.11.2 && dpkg-source -b . > ../source.log 2>&1)
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d -B > ../build.log 2>&1 || { tail -40 ../build.log; exit 1; }
tail -4 ../build.log; ls ..
'
