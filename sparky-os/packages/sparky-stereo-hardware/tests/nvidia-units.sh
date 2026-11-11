#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# NVIDIA's services wait for NVIDIA's driver: run in a debian:testing container (root, the host's /sys as Docker gives
# it) with the built package and NVIDIA's two unit files in /t. On a host with NVIDIA's driver loaded both conditions
# succeed and udev, at the driver's load, asks systemd for both services; without it both conditions fail.
#   docker run --rm -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v BUILD-CHECKOUT/tools/https-only-apt.sh:/run/https-only-apt.sh:ro -v DIR:/t:ro debian:testing sh /t/nvidia-units.sh    (DIR: the unit files, hw/ = the package unpacked)
set -u
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); a missing helper stops the script
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update >/dev/null && apt-get -qq install -y --no-install-recommends udev systemd >/dev/null 2>&1
cp /t/nvidia-persistenced.service /t/nvidia-powerd.service /usr/lib/systemd/system/
cp -a /t/hw/usr/lib/systemd/system/nvidia-persistenced.service.d /t/hw/usr/lib/systemd/system/nvidia-powerd.service.d /usr/lib/systemd/system/
cp /t/hw/usr/lib/udev/rules.d/71-sparky-stereo-nvidia-units.rules /usr/lib/udev/rules.d/
loaded=no; [ -e /sys/module/nvidia ] && loaded=yes
echo "== NVIDIA's driver loaded on this host: $loaded"
for u in nvidia-persistenced.service nvidia-powerd.service; do systemd-analyze condition --unit=$u 2>&1 | grep -v "^$"; done
if [ "$loaded" = yes ]; then
	echo "== udev at the driver's load (udevadm test, nothing applied)"
	udevadm test --action=add /sys/module/nvidia 2>&1 | grep -E "SYSTEMD_WANTS|^ *TAGS"
fi
