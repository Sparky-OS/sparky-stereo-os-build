#!/bin/bash
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
# No GPU or desktop is exposed while preparing the installed qualification image.
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export DEBIAN_FRONTEND=noninteractive
trap 'chown -R 1000:1000 /w' EXIT
printf 'deb [signed-by=/pub/sparky-stereo-repo.asc] file:/pub mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
if [ "$PHASE" = after ]; then
 printf 'deb [trusted=yes] file:/new ./\n' > /etc/apt/sources.list.d/edition-new.list
fi
apt-get -y update > /w/apt-update.log 2>&1
packages=(ffmpeg mpv libmpv-dev libmlt-dev libmlt++-dev libmlt-data melt qt6-multimedia-dev qml6-module-qtmultimedia kdenlive vlc-stereo libvlc-dev sparky-stereo-hardware pkgconf gcc g++ weston vulkan-tools vainfo)
if [ "$PHASE" = after ]; then
 packages+=(libmedia-gpu-route-dev media-gpu-route-tools libplacebo-dev)
else
 packages+=(libplacebo-dev=2:7.360.1-dmo1 libplacebo360=2:7.360.1-dmo1)
fi
apt-get -y --no-install-recommends install "${packages[@]}" > /w/apt-install.log 2>&1
mkdir -p /w/logs /w/final
sh /kit/packaging/build-installed-probes.sh > /w/probes-build.log 2>&1
dpkg-query -W -f='${binary:Package}\t${Version}\n' ffmpeg libavcodec63 libavcodec-dev mpv libmpv2 libmpv-dev libplacebo360 libmlt7 libmlt-dev libqt6multimedia6 kdenlive vlc-stereo sparky-stereo-hardware > /w/installed-versions.tsv
if [ "$PHASE" = after ]; then
 dpkg-query -W -f='${binary:Package}\t${Version}\n' libmedia-gpu-route0 >> /w/installed-versions.tsv
fi
