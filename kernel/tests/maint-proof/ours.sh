#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Our image packages in the steps of ref-debian.sh. /new has the build 11 image and headers of one flavour, /old the build 10 image
# (published scripts: run-parts, no symlinks). $1 = release 11, $2 = release 10, $3 = a newer fake release name.
set -eu
export DEBIAN_FRONTEND=noninteractive
P=/proof
R1=$1; R0=$2; R2=$3
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install initramfs-tools linux-base kmod >/dev/null 2>&1
sh $P/hooks-setup.sh
IMG1=$(ls /new/linux-image-${R1}_*_amd64.deb); HDR1=$(ls /new/linux-headers-${R1}_*_amd64.deb)
IMG0=$(ls /old/linux-image-${R0}_*_amd64.deb)
echo "== kernel 10 as published: $R0"
apt-get -y -qq --no-install-recommends install $IMG0 >/dev/null 2>&1
sh $P/state.sh "after installing build 10 ($R0)"
echo "== upgrade to build 11: $R1 (image and headers)"
apt-get -y -qq --no-install-recommends install $IMG1 $HDR1 >/dev/null 2>&1
sh $P/state.sh "after installing build 11 ($R1)"
echo "== a newer kernel $R2 (the same packages under another release name)"
mkdir -p /tmp/r
sh $P/repack.sh $IMG1 $R1 $R2 /tmp/r/linux-image-${R2}_x_amd64.deb
sh $P/repack.sh $HDR1 $R1 $R2 /tmp/r/linux-headers-${R2}_x_amd64.deb
apt-get -y -qq --no-install-recommends install /tmp/r/*.deb >/dev/null 2>&1
sh $P/state.sh "after installing $R2"
echo "== remove build 10 ($R0)"
dpkg --remove linux-image-$R0 >/dev/null 2>&1
sh $P/state.sh "after removing the image package of $R0"
echo "== reinstall build 11 over itself (an upgrade of the same package)"
dpkg -i --force-confnew $IMG1 >/dev/null 2>&1
sh $P/state.sh "after dpkg -i of $R1 over itself"
echo "== remove $R1 then $R2"
dpkg --remove linux-image-$R1 >/dev/null 2>&1
sh $P/state.sh "after removing the image package of $R1"
dpkg --remove linux-image-$R2 >/dev/null 2>&1
sh $P/state.sh "after removing the image package of $R2"
dpkg --audit && echo "dpkg --audit clean"
