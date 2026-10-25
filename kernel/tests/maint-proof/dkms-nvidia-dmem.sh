#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# usage: dkms-nvidia-dmem.sh RELEASE ; /repo = the edition's repository (NVIDIA's module source 615.71.09-2+stereo3d5),
# /lrepo = flat directory with the build's image and headers. The negative control of the headers' Breaks (build 13 on):
# the kernel has CONFIG_CGROUP_DMEM=y, and NVIDIA's module source before +stereo3d6 calls the pre-7.3
# dmem_cgroup_register_region(). 1. apt refuses to keep the old module source beside the new headers (it upgrades or
# removes it, never builds it). 2. Forced past the Breaks with dpkg, the DKMS build fails at the old call and the
# headers' postinst fails with it, which is why the Breaks is there.
set -uo pipefail
REL=$1
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
cp /lrepo/linux-image-${REL}_*.deb /lrepo/linux-headers-${REL}_*.deb /flat/ && rm -f /flat/*-lc-hr_*
(cd /flat && apt-ftparchive packages . > Packages)
echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/flat.list
apt-get -y update >/dev/null 2>&1
apt-get -y install dkms nvidia-kernel-open-dkms-stereo3d >/dev/null 2>&1
echo "== module source: $(dpkg-query -W -f='${Version}' nvidia-kernel-open-dkms-stereo3d)"
echo "== 1. apt with the Breaks (simulated)"
apt-get -s install linux-image-$REL linux-headers-$REL 2>&1 | grep -E "^(Inst|Remv|Conf) |Breaks|E: " | cut -c1-200
echo "== 2. dpkg past the Breaks: the image (no Breaks) and the headers' own dependencies through apt, then the headers by dpkg"
apt-get -y install linux-image-$REL > /tmp/image.log 2>&1; echo "image install exit $?"
apt-get -y install $(dpkg-deb -f /flat/linux-headers-${REL}_*.deb Depends | tr ',' '\n' | sed 's/(.*)//; s/|.*//; s/ //g' | grep -v '^\$' | sed 's/:.*//') > /tmp/deps.log 2>&1; echo "headers dependencies exit $?"
dpkg -i --force-breaks /flat/linux-headers-${REL}_*.deb > /tmp/dpkg.log 2>&1; echo "dpkg exit $?"
grep -E "Error!|error:|os-interface.c|dmem_cgroup_register_region|Autoinstall|returned error|subprocess .* returned" /tmp/dpkg.log | head -12 | cut -c1-220
f=$(ls /var/lib/dkms/nvidia/615.71.09/build/make.log 2>/dev/null); [ -n "$f" ] && grep -m3 -E "dmem_cgroup_register_region|error:" "$f" | cut -c1-220
echo "== package states"; dpkg-query -W -f='${Package} ${Status}\n' linux-image-$REL linux-headers-$REL
