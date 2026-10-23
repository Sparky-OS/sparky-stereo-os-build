#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Debian's own linux-image 7.2.11+deb14-amd64 (forky) in the same steps: the reference for ours.
set -eu
export DEBIAN_FRONTEND=noninteractive
P=/proof; D=/debs
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install initramfs-tools linux-base kmod >/dev/null 2>&1
sh $P/hooks-setup.sh
V1=7.2.11+deb14-amd64; V2=7.2.12+deb14-amd64
KP="linux-image-$V1 linux-binary-$V1 linux-modules-$V1 linux-base-$V1"
echo "== fresh install of $V1"
apt-get -y -qq --no-install-recommends install $D/linux-image-${V1}_7.2.11-1_amd64.deb $D/linux-binary-${V1}_7.2.11-1_amd64.deb $D/linux-modules-${V1}_7.2.11-1_amd64.deb $D/linux-base-${V1}_7.2.11-1_amd64.deb >/dev/null 2>&1
sh $P/state.sh "after installing $V1"
echo "== a newer kernel $V2 (the same packages under another release name)"
mkdir -p /tmp/r
for p in linux-image linux-binary linux-modules linux-base; do
    sh $P/repack.sh $D/${p}-${V1}_7.2.11-1_amd64.deb $V1 $V2 /tmp/r/${p}-${V2}_7.2.11-1_amd64.deb
done
apt-get -y -qq --no-install-recommends install /tmp/r/*.deb >/dev/null 2>&1
sh $P/state.sh "after installing $V2"
echo "== remove $V1"
dpkg --remove linux-image-$V1 >/dev/null 2>&1
sh $P/state.sh "after removing the image package of $V1"
echo "== remove $V2"
dpkg --remove linux-image-$V2 >/dev/null 2>&1
sh $P/state.sh "after removing the image package of $V2"
dpkg --audit && echo "dpkg --audit clean"
