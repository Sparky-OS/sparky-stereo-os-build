#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
mkdir -p /build/proof-home
export HOME=/build/proof-home
rm -f /etc/apt/apt.conf.d/docker-clean
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' >/etc/apt/preferences.d/stereo-rig
apt-get -y update
apt-get -y --no-install-recommends install gpgv
dpkg -i /var/local/sparky-stereo-repo/carried/deb-multimedia-keyring_2024.9.1_all.deb
printf '%s\n' 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] http://www.deb-multimedia.org forky main' >/etc/apt/sources.list.d/deb-multimedia.list
apt-get -y update
packages=()
if [ "${1:-}" != --dependencies-only ]; then
    for deb in /build/sources/*.deb; do
        [[ $deb == *-dbgsym_* ]] || packages+=("$deb")
    done
    test "${#packages[@]}" -gt 10
fi
apt-get -y --no-install-recommends install "${packages[@]}" \
    build-essential cmake ninja-build pkgconf libgl-dev libegl-dev libx11-dev \
    qt6-base-private-dev qt6-declarative-dev libstereo-declare-dev libwayland-dev \
    wayland-protocols plasma-wayland-protocols python3-numpy python3-pil python3-tk \
    python3-dbus python3-gi xvfb xauth mesa-utils x11-utils x11-xserver-utils \
    paraview python3-paraview dbus-x11 kwin-wayland kscreen systemsettings \
    sparky-stereo-power-profiles procps libcap2-bin lintian
apt-get clean
# This account is confined to the fresh proof filesystem/container.
getent group 1000 >/dev/null || groupadd -g 1000 stereo-test
getent passwd 1000 >/dev/null || useradd -u 1000 -g 1000 -m -s /bin/bash stereo-test
passwd -l stereo-test
mkdir -p /build/installed-tests
chmod 755 /build/installed-tests
# Do not grant a file capability to the private virtual-backend compositor.
setcap -r /usr/bin/kwin_wayland 2>/dev/null || true
dpkg --audit
dpkg-query -W > /build/logs/installed-packages.txt
