#!/bin/bash
docker rm -f qtmm-img2 >/dev/null 2>&1
docker run --name qtmm-img2 --platform linux/amd64 --cpus 4 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/partners/queue/plank-player/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive qtmm-build:1 bash -c '
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades build-dep dragon 2>&1 | tail -2
apt-get -y --allow-downgrades install dh-sequence-kf6 libkf6i18n-dev libkirigami-dev extra-cmake-modules qt6-multimedia-dev qml6-module-qtmultimedia 2>&1 | tail -2
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit qtmm-img2 qtmm-build:2 >/dev/null; docker rm qtmm-img2 >/dev/null; echo imgdone
