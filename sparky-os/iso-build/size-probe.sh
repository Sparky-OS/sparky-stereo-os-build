#!/bin/sh
set -eu
/build/apt-setup.sh / >/dev/null 2>&1
apt-get update -qq >/dev/null 2>&1 || true
/build/base-list.sh > /tmp/base
sim() { apt-get -s -o Debug::NoLocking=1 install "$@" > /tmp/sim.txt 2>&1 || { grep -A12 'conflicting assignments' /tmp/sim.txt | head -14; return 0; }; python3 /build/sim-size.py < /tmp/sim.txt; }
EDITION="sparky-stereo-desktop sparky-stereo-system sparky-stereo-hardware-support sparky-stereo-look"
NV="nvidia-driver=615.71.09-2 nvidia-kernel-open-dkms-stereo3d libnvcuvid1=615.71.09-2 nvidia-vaapi-driver linux-image-amd64"
echo "== A: Sparky KDE base"; sim $(cat /tmp/base)
echo "== B: base + edition metas with Recommends"; sim $(cat /tmp/base) $EDITION
echo "== C: base + edition metas, no Recommends"; sim --no-install-recommends $(cat /tmp/base) $EDITION
echo "== D: B + NVIDIA 615 + Debian kernel"; sim $(cat /tmp/base) $EDITION $NV
echo "== E: C + NVIDIA 615 + Debian kernel"; sim --no-install-recommends $(cat /tmp/base) $EDITION $NV
