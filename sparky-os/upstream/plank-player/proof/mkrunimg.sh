#!/bin/bash
# usage: mkrunimg.sh <tag> <dir with the plank-player deb | "repo">: debian:testing + our repo + headless KWin + plank-player
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
tag=$1; dir=$2
docker rm -f plank-runimg >/dev/null 2>&1
if [ "$dir" = repo ]; then inst=plank-player; mnt=/tmp; else inst=$(ls $dir/plank-player_*_amd64.deb | sed 's#.*/#/pk/#'); mnt=$dir; fi
docker run --name plank-runimg --platform linux/amd64 --cpus 4 -v ${SPARKY_REPO_DIR:?}:/repo:ro -v ${SPARKY_WORKSPACES:?}/plank-player/run/pin:/pin:ro -v $mnt:/pk:ro -e DEBIAN_FRONTEND=noninteractive debian:testing bash -c '
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install kwin-wayland libgl1-mesa-dri libegl-mesa0 libglx-mesa0 libgbm1 libstereo-declare1 mesa-vulkan-drivers python3-numpy python3-pil dbus-x11 dbus qml6-module-org-kde-desktop breeze-icon-theme fonts-dejavu-core wayland-utils qt6-wayland ffmpeg '"$inst"' 2>&1 | tail -15
dpkg -l | grep -E "^ii  (plank-player|libqt6multimedia6|kwin-wayland|libgl1-mesa-dri|libstereo-declare1|qml6-module-org-kde-bigscreen) " | awk "{print \$2,\$3}"
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit plank-runimg $tag >/dev/null; docker rm plank-runimg >/dev/null; echo imgdone
