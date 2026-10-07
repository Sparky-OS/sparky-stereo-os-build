#!/bin/bash
# usage: mkrunimg.sh <tag> <out dir with plasmatube deb>: debian:testing + our repo + headless KWin + plasmatube from that dir
tag=$1; dir=$2
docker rm -f pt-runimg >/dev/null 2>&1
docker run --name pt-runimg --platform linux/amd64 --cpus 4 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/partners/queue/plasmatube/run/pin:/pin:ro -v $dir:/pt:ro -e DEBIAN_FRONTEND=noninteractive debian:testing bash -c '
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install kwin-wayland libgl1-mesa-dri libegl-mesa0 libglx-mesa0 libgbm1 libstereo-declare1 mesa-vulkan-drivers python3-numpy python3-pil dbus-x11 dbus xvfb xauth qml6-module-org-kde-desktop breeze-icon-theme fonts-dejavu-core wayland-utils qt6-wayland mpv ffmpeg /pt/plasmatube_*_amd64.deb 2>&1 2>&1 | tail -25
dpkg -l | grep -E "^ii  (plasmatube|libmpvqt3|libmpv2|kwin-wayland|libgl1-mesa-dri|libstereo-declare1) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit pt-runimg $tag >/dev/null; docker rm pt-runimg >/dev/null; echo imgdone
