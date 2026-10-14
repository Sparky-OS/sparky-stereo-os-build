#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 0
export DEBIAN_FRONTEND=noninteractive
apt-get -y --reinstall --no-install-recommends install /packages/gl-stereo*_0.3.0-1_*.deb /packages/libstereoshow*_0.3.0-1_*.deb /packages/xscreensaver*_6.09+dfsg1-2+stereo3d2_*.deb plasma-desktop=4:6.7.4-1+stereo3d1
mkdir -p /build/home
chown 1000:1000 /build/home /home/stereo-test
chmod 666 /usr/share/gl-stereo/catalogue.json
dpkg-query -W 'gl-stereo*' 'libstereoshow*' 'xscreensaver*' kwin-wayland libqt6core6t64 libstereo-declare1 plasma-desktop libkscreenlocker6 > /build/final-installed-packages.txt
chown 1000:1000 /build/final-installed-packages.txt
sha256sum /packages/gl-stereo*_0.3.0-1_*.deb /packages/libstereoshow*_0.3.0-1_*.deb /packages/xscreensaver*_6.09+dfsg1-2+stereo3d2_*.deb > /build/final-installed-debs.sha256
chown 1000:1000 /build/final-installed-debs.sha256
