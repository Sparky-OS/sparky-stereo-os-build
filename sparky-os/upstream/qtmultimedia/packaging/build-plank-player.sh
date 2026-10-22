#!/bin/bash
# usage: build-plank-player.sh [work dir, default ${SPARKY_SCRATCH}/qtmm-lane/pkg-plank]
# plank-player 5.27.80+git20261005.f87e775-1+stereo3d2: KDE's master at f87e775 (the orig tarball of +stereo3d1), our two patches
# (plank-player/*.patch: the 3D menu bound to Qt Multimedia's Video, and the Return key fix), packaging/ from ./plank-player-debian,
# built in plank-build:1 as the user
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -e
W=${1:-${SPARKY_SCRATCH:?}/qtmm-lane/pkg-plank}
H=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p $W/patches $W/home
cp $H/plank-player/*.patch $W/patches/
cp -r $H/packaging/plank-player-debian $W/
cp ${SPARKY_WORKSPACES:?}/plank-player/outA/plank-player_5.27.80+git20261005.f87e775.orig.tar.xz $W/
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -e DEBIAN_FRONTEND=noninteractive \
  -v $W:/w -v ${SPARKY_REPO_DIR:?}:/repo:ro plank-build:1 bash -c '
set -e
cd /w; U=5.27.80+git20261005.f87e775
rm -rf plank-player-$U; tar xf plank-player_$U.orig.tar.xz
cd plank-player-$U
mkdir -p debian/source debian/patches
cp /w/plank-player-debian/{control,rules,copyright,changelog} debian/; cp /w/plank-player-debian/source/format debian/source/
cp /w/patches/*.patch debian/patches/; ls /w/patches/*.patch | xargs -n1 basename > debian/patches/series
mkdir -p ../srcpkg && cp -a . ../srcpkg/plank-player-$U && cp ../plank-player_$U.orig.tar.xz ../srcpkg/
(cd ../srcpkg/plank-player-$U && dpkg-source -b . > ../source.log 2>&1)
dpkg-buildpackage -us -uc -d -j4 > ../build.log 2>&1 || { tail -40 ../build.log; exit 1; }
tail -3 ../build.log; ls ..
'
