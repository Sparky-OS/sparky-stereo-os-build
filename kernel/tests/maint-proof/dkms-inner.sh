#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: dkms-inner.sh RELEASE ORDER ; /repo = the edition's repository, /lrepo = flat directory with the build's image, headers and metas
# (and, from build 13, nvidia-kernel-open-dkms-stereo3d and sparky-stereo-nvidia-driver-lock 615.71.09-2+stereo3d6)
# Clean forky amd64 container. Proves: DKMS builds NVIDIA open, xpadneo, acpi-call, v4l2loopback, vhba and xone against the new headers,
# for both install orders; the compiler of the headers' Depends is the one the kernel was built with.
set -uo pipefail
REL=$1; ORDER=$2
export DEBIAN_FRONTEND=noninteractive
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf 'Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n' > /etc/apt/sources.list.d/sparky.sources
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky
apt-get -y update >/dev/null 2>&1
apt-get -y install apt-utils >/dev/null 2>&1
mkdir -p /stub/a/DEBIAN /stub/b/DEBIAN /flat
printf 'Package: firmware-nvidia-gsp\nVersion: 615.71.09-2\nArchitecture: amd64\nMaintainer: Stub\nDescription: EMPTY STUB for this test: the real package comes from NVIDIA repository, not from the edition repo\n' > /stub/a/DEBIAN/control
printf 'Package: nvidia-installer-cleanup\nVersion: 1\nArchitecture: amd64\nMaintainer: Stub\nDescription: EMPTY STUB for this test (NVIDIA repository package)\n' > /stub/b/DEBIAN/control
dpkg-deb -b /stub/a /flat/firmware-nvidia-gsp_615.71.09-2_amd64.deb >/dev/null; dpkg-deb -b /stub/b /flat/nvidia-installer-cleanup_1_amd64.deb >/dev/null
cp /lrepo/*.deb /flat/ && rm -f /flat/*-lc-hr_*
(cd /flat && apt-ftparchive packages . > Packages)
echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/flat.list
# the flat directory wins for the kernel and, from build 13, for the NVIDIA module source that build needs (+stereo3d6)
printf 'Package: linux-image-* linux-headers-* linux-image-sparky-stereo* linux-headers-sparky-stereo* nvidia-kernel-open-dkms-stereo3d sparky-stereo-nvidia-driver-lock\nPin: origin ""\nPin-Priority: 1002\n' > /etc/apt/preferences.d/flat
apt-get -y update >/dev/null 2>&1
echo "== candidate versions"; apt-cache policy linux-image-$REL linux-headers-$REL | grep -E "^linux|Candidate"
echo "== dwarves/pahole/g++/gcc before: $(dpkg -l pahole dwarves g++ gcc 2>/dev/null | grep -c '^ii')"
DK="dkms acpi-call-dkms v4l2loopback-dkms vhba-dkms xpadneo-dkms nvidia-kernel-open-dkms-stereo3d"
# xone-dkms depends on linux-headers-generic, which the headers meta provides (212c)
META=linux-headers-sparky-stereo
case "$REL" in *-v3) META=linux-headers-sparky-stereo-v3;; *-rt-*) META=linux-headers-sparky-stereo-rt;; esac
quiet() { grep -E "Autoinstall|rror|succeeded|Setting up linux|Unpacking linux|E: |W: .*gcc" | cut -c1-220; }
case $ORDER in
 image-first)
   apt-get -y install $DK xone-dkms 2>&1 | tail -n 2
   apt-get -y install linux-image-$REL 2>&1 | quiet
   apt-get -y install linux-headers-$REL $META 2>&1 | quiet;;
 headers-first)
   apt-get -y install $DK xone-dkms 2>&1 | tail -n 2
   apt-get -y install linux-headers-$REL $META 2>&1 | quiet
   apt-get -y install linux-image-$REL 2>&1 | quiet;;
esac
echo "== headers Depends: $(dpkg-query -W -f='${Depends}' linux-headers-$REL)"
echo "== compiler: $(grep CONFIG_CC_VERSION_TEXT /usr/src/linux-headers-$REL/.config); installed: $(dpkg-query -W -f='${Package} ${Version}\n' 'gcc-*-for-host' 2>/dev/null | tr '\n' ' ')"
echo "== pahole: $(dpkg-query -W -f='${Package} ${Version}\n' pahole)"
echo "== dkms status"; dkms status
echo "== modules"; find /lib/modules/$REL/updates -name '*.ko*' | sort | while read f; do echo "$f signer=$(modinfo -F signer $f) vermagic=$(modinfo -F vermagic $f | cut -d' ' -f1)"; done
echo "== which kernels does DKMS know: $(dkms status | awk -F', ' '{print $2}' | sort -u | tr '\n' ' ')"
echo "== extras of build 11: kconfig/conf extract-cert relocs source link"
ls -l /usr/src/linux-headers-$REL/scripts/kconfig/conf /usr/src/linux-headers-$REL/certs/extract-cert /usr/src/linux-headers-$REL/arch/x86/tools/relocs /lib/modules/$REL/source /lib/modules/$REL/build | awk '{print $1,$5,$9,$10,$11}'
dpkg --audit && echo "dpkg --audit clean"
