#!/bin/bash
# build the stereo dragonplayer: Debian's source + our two patches (inside the build image, as the user)
set -e
cd /w/build/dragon
rm -rf tree; mkdir tree; cd tree
apt-get source dragon >/dev/null 2>&1
cd dragon-26.04.0
mkdir -p debian/patches
cp /w/src/dragon-patches/*.patch debian/patches/
ls debian/patches/*.patch | xargs -n1 basename > debian/patches/series
sed -i 's/^Build-Depends: debhelper-compat (= 13),/Build-Depends: debhelper-compat (= 13),\n               libstereo-declare-dev,\n               libwayland-dev,\n               qt6-base-private-dev,\n               wayland-protocols,/' debian/control
sed -i 's/^Depends: ${misc:Depends},/Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d2),\n         ${misc:Depends},/' debian/control
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 4:26.04.0-1+stereo3d2 -D UNRELEASED "Show one view of a stereoscopic 3D video of any packing, with the 3D Video menu and a manual input format; show both views to the compositor as stereo content under our KWin (the controls stay over the video, the same in both eyes)" 2>&1 | tail -1
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d 2>&1 | tail -5
