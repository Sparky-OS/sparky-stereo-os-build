#!/bin/bash
docker rm -f qtmm-runimg4 >/dev/null 2>&1
docker run --name qtmm-runimg4 --platform linux/amd64 --cpus 2 -v /K3D/temp/sparky-os/repo:/repo:ro -v /K3D/temp/qtmm-lane/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive qtmm-run:3 bash -c '
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install pipewire pipewire-bin pipewire-pulse wireplumber pulseaudio-utils sox libsoxr0 2>&1 | tail -3
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit qtmm-runimg4 qtmm-run:4 >/dev/null; docker rm qtmm-runimg4 >/dev/null; echo imgdone
