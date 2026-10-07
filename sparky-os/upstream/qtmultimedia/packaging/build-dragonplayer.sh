#!/bin/bash
# usage: build-dragonplayer.sh [work dir, default /K3D/temp/qtmm-lane/pkg-dragon]
# dragonplayer 4:26.04.0-1+stereo3d4: Debian's source with our one patch (dragon/0001-*.patch, QML only: the 3D Video menu bound to
# Qt Multimedia's VideoOutput), built in a throwaway debian:testing container (as the user, 4 threads)
set -e
W=${1:-/K3D/temp/qtmm-lane/pkg-dragon}
H=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p $W/patches $W/home
cp $H/dragon/*.patch $W/patches/
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -e DEBIAN_FRONTEND=noninteractive \
  -v $W:/w -v /K3D/temp/sparky-os/repo:/repo:ro qtmm-build:2 bash -c '
set -e
cd /w; rm -rf tree; mkdir tree; cd tree
apt-get source dragon >/dev/null 2>&1
cd dragon-26.04.0
mkdir -p debian/patches
cp /w/patches/*.patch debian/patches/
ls /w/patches/*.patch | xargs -n1 basename > debian/patches/series
# what the QML needs: Qt Multimedia with the stereo properties of VideoOutput
sed -i "s/^Depends: \${misc:Depends},/Depends: libqt6multimedia6 (>= 6.11.2-3+stereo3d4~),\n         qml6-module-org-kde-coreaddons,\n         qml6-module-org-kde-config,\n         qml6-module-org-kde-kirigami,\n         qml6-module-qt-labs-animation,\n         qml6-module-qtcore,\n         qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d4~),\n         qml6-module-qtquick,\n         qml6-module-qtquick-controls,\n         qml6-module-qtquick-dialogs,\n         qml6-module-qtquick-effects,\n         qml6-module-qtquick-layouts,\n         qml6-module-qtquick-templates,\n         qml6-module-qtquick-window,\n         \${misc:Depends},/" debian/control
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 4:26.04.0-1+stereo3d4 -D UNRELEASED "Depend on every QML module the program imports (kirigami, coreaddons, config, QtCore, QtQuick and its Controls, Dialogs, Effects, Layouts, Templates and Window, Qt.labs.animation: without them a stock install fails to start with module not installed), and on Qt Multimedia +stereo3d4" 2>&1 | tail -1
mkdir -p ../srcpkg && cp -a . ../srcpkg/dragon-26.04.0 && cp ../dragon_26.04.0.orig.tar.xz* ../srcpkg/
(cd ../srcpkg/dragon-26.04.0 && dpkg-source -b . > ../source.log 2>&1)
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc -j4 -d > ../build.log 2>&1 || { tail -30 ../build.log; exit 1; }
tail -3 ../build.log; ls ..
'
