#!/bin/bash
# usage: build.sh <outdir> <patches dir or ->  : builds plank-player from <outdir>'s orig tarball with packaging/ (+ patches/) in plank-build:1, as the user
out=$1; patches=$2
W=/K3D/temp/partners/queue/plank-player
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/tmp/h -e DEBIAN_FRONTEND=noninteractive \
  -v $W:/w -v /K3D/temp/sparky-os/repo:/repo:ro plank-build:1 bash -c '
set -e
cd /w/'$out'
U=5.27.80+git20261005.f87e775
rm -rf plank-player-$U; tar xf plank-player_$U.orig.tar.xz
cd plank-player-$U
mkdir -p debian; cp /w/packaging/{control,rules,copyright,changelog} debian/; mkdir -p debian/source; cp /w/packaging/source/format debian/source/
if [ "'$patches'" != "-" ]; then mkdir -p debian/patches; cp /w/'$patches'/*.patch debian/patches/; (cd debian/patches; ls *.patch > series); fi
dpkg-buildpackage -us -uc -d -j4 > ../build.log 2>&1 || { tail -40 ../build.log; exit 1; }
cd ..; tail -3 build.log; ls
'
