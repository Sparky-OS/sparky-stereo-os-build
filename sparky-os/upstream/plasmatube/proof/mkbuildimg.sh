#!/bin/bash
# build image: debian:testing + our development repository + PlasmaTube's build dependencies
docker rm -f pt-img >/dev/null 2>&1
docker run --name pt-img --platform linux/amd64 --cpus 4 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/partners/queue/plasmatube/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive debian:testing bash -c '
set -e
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install build-essential debhelper dh-sequence-kf6 devscripts fakeroot lintian extra-cmake-modules cmake pkgconf qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-svg-dev libkf6coreaddons-dev libkf6config-dev libkf6i18n-dev libkirigami-dev libkf6dbusaddons-dev libkf6windowsystem-dev kirigami-addons-dev libmpvqt-dev libmpv-dev qtkeychain-qt6-dev gettext dpkg-dev 2>&1 | tail -3
dpkg -l | grep -E "^ii  (libmpvqt|libmpv2|libmpv-dev|qt6-base-dev) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list
'
docker commit pt-img plasmatube-build:1 >/dev/null; docker rm pt-img >/dev/null; echo imgdone
