#!/bin/bash
docker rm -f qtmm-img >/dev/null 2>&1
docker run --name qtmm-img --platform linux/amd64 --cpus 4 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/partners/queue/plank-player/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive debian:testing-slim bash -c '
set -e
apt-get -y update >/dev/null 2>&1; apt-get -y dist-upgrade 2>&1 | tail -1
apt-get -y install ca-certificates >/dev/null 2>&1
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
sed -i "s/^Types: deb$/Types: deb deb-src/" /etc/apt/sources.list.d/debian.sources
apt-get -y update 2>&1 | tail -1
apt-get -y --allow-downgrades build-dep qt6-multimedia 2>&1 | tail -3
apt-get -y --allow-downgrades install devscripts fakeroot dpkg-dev quilt ccache qt6-base-private-dev qt6-wayland-dev qt6-wayland-private-dev qt6-declarative-private-dev libstereo-declare-dev libwayland-dev wayland-protocols libsoxr-dev libegl-dev libgles-dev pkgconf git 2>&1 | tail -3
dpkg -l | grep -E "^ii  (libqt6core6t64|libqt6multimedia6|libstereo-declare-dev|libavcodec-dev) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit qtmm-img qtmm-build:1 >/dev/null; docker rm qtmm-img >/dev/null; echo imgdone
