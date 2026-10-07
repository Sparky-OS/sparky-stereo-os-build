#!/bin/bash
# build image: debian:testing + our development repository + Plank Player's build dependencies
docker rm -f plank-img >/dev/null 2>&1
docker run --name plank-img --platform linux/amd64 --cpus 4 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/partners/queue/plank-player/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive debian:testing bash -c '
set -e
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install build-essential debhelper dh-sequence-kf6 devscripts fakeroot lintian extra-cmake-modules cmake pkgconf qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-multimedia-dev libkf6i18n-dev libkirigami-dev gettext dpkg-dev libstereo-declare-dev libwayland-dev wayland-protocols qt6-wayland-dev qt6-wayland-dev-tools libxkbcommon-dev 2>&1 | tail -3
dpkg -l | grep -E "^ii  (libqt6multimedia6|qt6-base-dev|libstereo-declare-dev|libkf6i18n-dev|libkirigami-dev) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list
'
docker commit plank-img plank-build:1 >/dev/null; docker rm plank-img >/dev/null; echo imgdone
