#!/bin/bash
# build image: debian:testing + our development repository + Marble's build dependencies + the test rig
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker rm -f marble-img >/dev/null 2>&1
docker run --name marble-img --platform linux/amd64 --cpus 4 -v ${SPARKY_REPO_DIR:?}:/repo:ro -v ${SPARKY_SCRATCH:?}/marble-lane/work/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive debian:testing bash -c '
set -e
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install build-essential debhelper dh-sequence-kf6 dh-sequence-pkgkde-symbolshelper dh-sequence-qmldeps devscripts fakeroot lintian cmake extra-cmake-modules gettext libabsl-dev libgps-dev libkf6config-dev libkf6coreaddons-dev libkf6crash-dev libkf6doctools-dev libkf6i18n-dev libkf6kio-dev libkf6parts-dev libkf6runner-dev libphonon4qt6-dev libphonon4qt6experimental-dev libplasma-dev libprotobuf-dev libprotoc-dev libshp-dev pkg-kde-tools pkgconf protobuf-compiler qml6-module-org-kde-kcmutils qml6-module-org-kde-kirigamiaddons-formcard qml6-module-org-kde-plasma-plasma5support qt6-5compat-dev qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-multimedia-dev qt6-positioning-dev qt6-serialport-dev qt6-svg-dev qt6-tools-dev qt6-webengine-dev shared-mime-info zlib1g-dev libstereo-declare-dev libwayland-dev wayland-protocols kwin-wayland xwayland dbus-x11 dbus-user-session python3 python3-numpy python3-pil libgl1-mesa-dri mesa-vulkan-drivers qt6-wayland xdotool libqt6dbus6 gdb clang-format 2>&1 | tail -5
dpkg -l | grep -E "^ii  (kwin-wayland|libgl1-mesa-dri|qt6-base-dev|libstereo-declare-dev) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list
'
docker commit marble-img marble-build:1 >/dev/null; docker rm marble-img >/dev/null; echo imgdone
