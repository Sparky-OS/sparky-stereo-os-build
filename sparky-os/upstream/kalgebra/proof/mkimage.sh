#!/bin/bash
set -eu
export DEBIAN_FRONTEND=noninteractive
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/sparky-dev.list
sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
printf 'Package: *\nPin: origin ""\nPin-Priority: 1001\n' > /etc/apt/preferences.d/dev-repo
apt-get update -qq
apt-get install -y --no-install-recommends kwin-wayland=4:6.7.4-2+stereo3d13+1 kwin-common=4:6.7.4-2+stereo3d13+1 kwin-data=4:6.7.4-2+stereo3d13+1 libkwin6 libegl-mesa0 libglx-mesa0 libgl1-mesa-dri mesa-libgallium libstereo-declare1 xwayland x11-utils mesa-utils dbus-x11 dbus libgbm1 qt6-wayland xvfb xauth python3 python3-pil python3-numpy build-essential devscripts fakeroot dpkg-dev ninja-build 2>&1 | tail -5
dpkg -l | grep -E "kwin-wayland|libegl-mesa0|mesa-libgallium|libstereo-declare1|qt6-base-dev " | awk '{print $2,$3}'
