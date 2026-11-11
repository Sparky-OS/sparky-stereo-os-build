#!/bin/bash
# SUPERSEDED (ORDER 453b): history of the +stereo3d1 state; the shipped recipe is in sparky-os/upstream/qtmultimedia, see README.md beside this file
# build the stereo dragonplayer: Debian's source + our two patches (inside the build image, as the user)
set -e
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
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
dch --date "$SOURCE_DATE_RFC2822" -v 4:26.04.0-1+stereo3d2 -D UNRELEASED "Show one view of a stereoscopic 3D video of any packing, with the 3D Video menu and a manual input format; show both views to the compositor as stereo content under our KWin (the controls stay over the video, the same in both eyes)" 2>&1 | tail -1
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d 2>&1 | tail -5
