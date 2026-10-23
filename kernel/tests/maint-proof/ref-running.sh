#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Debian's image under the name of the running kernel (the host's uname -r is what POSIX::uname sees in a container too)
set -eu
export DEBIAN_FRONTEND=noninteractive
P=/proof; D=/debs
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install initramfs-tools linux-base kmod debconf-utils >/dev/null 2>&1
sh $P/hooks-setup.sh
V1=7.2.11+deb14-amd64; RUN=$(uname -r)
echo "running kernel (uname -r): $RUN"
mkdir -p /tmp/r
for p in linux-image linux-binary linux-modules linux-base; do
    sh $P/repack.sh $D/${p}-${V1}_7.2.11-1_amd64.deb $V1 $RUN /tmp/r/${p}-${RUN}_7.2.11-1_amd64.deb
done
apt-get -y -qq --no-install-recommends install /tmp/r/*.deb >/dev/null 2>&1
echo "== removal with DEBIAN_FRONTEND=noninteractive"
dpkg --remove linux-image-$RUN 2>&1 | tail -n 4; echo "rc=$?"; dpkg -l linux-image-$RUN | tail -n 1 | cut -c1-60
echo "== reinstall, then removal with the readline frontend and no answer on stdin"
dpkg -i /tmp/r/linux-image-${RUN}_7.2.11-1_amd64.deb >/dev/null 2>&1
DEBIAN_FRONTEND=readline dpkg --remove linux-image-$RUN < /dev/null 2>&1 | tail -n 6; echo "dpkg rc=$?"
dpkg -l linux-image-$RUN | tail -n 1 | cut -c1-60
echo "== the same with an answer: debconf says abort=false"
echo "linux-base linux-base/removing-running-kernel boolean false" | debconf-set-selections
DEBIAN_FRONTEND=readline dpkg --remove linux-image-$RUN < /dev/null 2>&1 | tail -n 6
dpkg -l linux-image-$RUN | tail -n 1 | cut -c1-60
