#!/bin/bash
# build the stereo kdenlive: Debian's source + our two patches (inside the kd build image, as the user)
set -e
cd /w/build/kdenlive
rm -rf tree; mkdir tree; cd tree
apt-get source kdenlive >/dev/null 2>&1
cd kdenlive-26.08.1
mkdir -p debian/patches
cp /w/src/kdenlive-patches/*.patch debian/patches/
ls debian/patches/*.patch | xargs -n1 basename > debian/patches/series
sed -i '0,/^Build-Depends: /s//Build-Depends: libstereo-declare-dev,\n               libwayland-dev,\n               qt6-base-private-dev,\n               wayland-protocols,\n               /' debian/control
sed -i '0,/^Depends: \${shlibs:Depends},/s//Depends: libmlt7 (>= 7.40.0-1+stereo3d2),\n         ${shlibs:Depends},/' debian/control
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 26.08.1-1+stereo3d2 -D UNRELEASED "Know the packing of a stereoscopic 3D video (clip properties, monitor preview, render); the monitor itself shows the video in 3D under our KWin" 2>&1 | tail -1
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d 2>&1 | tail -5
