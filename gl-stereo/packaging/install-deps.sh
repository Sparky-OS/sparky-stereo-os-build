#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
mkdir -p /build/home
rm -f /etc/apt/apt.conf.d/docker-clean
dpkg --configure -a
apt-get -y update
apt-get -y --no-install-recommends --fix-broken install
apt-get -y --no-install-recommends install gpgv
dpkg -i /var/local/sparky-stereo-repo/carried/deb-multimedia-keyring_2024.9.1_all.deb
printf '%s\n' 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] http://www.deb-multimedia.org forky main' >/etc/apt/sources.list.d/deb-multimedia.list
apt-get -y update
apt-get -y --no-install-recommends build-dep kscreenlocker plasma-desktop xscreensaver
apt-get -y --no-install-recommends install build-essential dpkg-dev debhelper devscripts lintian fakeroot \
    libstereo-declare-dev cmake ninja-build libgl-dev libegl-dev libx11-dev libwayland-dev wayland-protocols \
    python3-numpy python3-pil python3-tk mesa-utils xvfb libkf6idletime-dev libkscreen-dev \
    qt6-base-private-dev plasma-wayland-protocols x11-utils x11-xserver-utils dbus-x11
apt-get clean
dpkg-query -W qt6-base-dev libkf6config-dev libstereo-declare-dev > /build/logs/build-versions.txt
