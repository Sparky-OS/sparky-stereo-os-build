#!/bin/bash
# a fresh debian:testing + our repository (pinned) + headless KWin + the three programs, installed from the repository
docker rm -f qtmm-fresh >/dev/null 2>&1
docker run --name qtmm-fresh --platform linux/amd64 --cpus 4 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/qtmm-lane/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive debian:testing bash -c '
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install kwin-wayland libgl1-mesa-dri libegl-mesa0 libglx-mesa0 libgbm1 libstereo-declare1 mesa-vulkan-drivers python3-numpy python3-pil dbus-x11 dbus qml6-module-org-kde-desktop breeze-icon-theme fonts-dejavu-core wayland-utils qt6-wayland ffmpeg dragonplayer plank-player qml6-module-qt-labs-animation qml6-module-qtquick-dialogs qml-qt6 qml6-module-qtquick-window qml6-module-qtquick-controls pipewire pipewire-bin pipewire-pulse wireplumber pulseaudio-utils 2>&1 | tail -4
dpkg -l | grep -E "^ii  (plank-player|dragonplayer|libqt6multimedia6|qml6-module-qtmultimedia|kwin-wayland|libgl1-mesa-dri|libstereo-declare1|libqt6core6t64|ffmpeg) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit qtmm-fresh qtmm-fresh:1 >/dev/null; docker rm qtmm-fresh >/dev/null; echo imgdone
