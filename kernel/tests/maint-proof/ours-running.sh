#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install initramfs-tools linux-base kmod >/dev/null 2>&1
RUN=$(uname -r); IMG=$(ls /new/linux-image-7.3.0-rc6-stereo3d11_*.deb)
echo "running kernel: $RUN"
sh /proof/repack.sh $IMG 7.3.0-rc6-stereo3d11 $RUN /tmp/run.deb
apt-get -y -qq --no-install-recommends install /tmp/run.deb >/dev/null 2>&1
echo "== removal, readline frontend, no answer"
DEBIAN_FRONTEND=readline dpkg --remove linux-image-$RUN < /dev/null 2>&1 | tail -n 5; dpkg -l linux-image-$RUN | tail -n1 | cut -c1-50
echo "== removal, noninteractive frontend"
dpkg --remove linux-image-$RUN 2>&1 | grep -E "^W:|^E:"; dpkg -l linux-image-$RUN | tail -n1 | cut -c1-50
