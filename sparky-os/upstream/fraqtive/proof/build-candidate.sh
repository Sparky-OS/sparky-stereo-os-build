#!/bin/sh
# build-candidate.sh SRC_DIR OUT_DIR: Debian's fraqtive source plus this folder's patches, as a binary package (run in a container
# that has build-essential, qtbase5-dev, qt5-qmake, libglu1-mesa-dev, debhelper, devscripts; apt sources with deb-src).
# SRC_DIR is empty; OUT_DIR receives the .deb. The version is 0.4.8.1-1+stereo3d1 (a +stereo3dN successor of Debian's 0.4.8.1-1).
set -eu
src=$1; out=$2
here=$(cd "$(dirname "$0")/.." && pwd)
cd "$src"
apt-get source --download-only fraqtive=0.4.8.1-1
dpkg-source -x fraqtive_0.4.8.1-1.dsc
cd fraqtive-0.4.8.1
cp "$here"/patches/0001-*.patch debian/patches/03-vertex-arrays-with-current-context.diff
cp "$here"/patches/0002-*.patch debian/patches/04-qopenglwidget-for-wayland.diff
printf '03-vertex-arrays-with-current-context.diff\n04-qopenglwidget-for-wayland.diff\n' >> debian/patches/series
DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)' \
	dch -v 0.4.8.1-1+stereo3d1 -D testing --force-distribution "Draw the 3D view: vertex arrays set with a current context, and QOpenGLWidget so that it works on Wayland (ORDER 28)"
dpkg-buildpackage -b -us -uc
cp ../fraqtive_0.4.8.1-1+stereo3d1_amd64.deb "$out"/
