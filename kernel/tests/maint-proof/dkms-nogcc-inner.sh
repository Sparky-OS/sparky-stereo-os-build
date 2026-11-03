#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# dkms-nogcc-inner.sh RELEASE ORDER EXPECT MODE: DKMS with no plain gcc command (ORDER 361's finding, ORDER 364's proof).
# Clean Debian testing amd64 container; /repo the edition's published repository (a local copy), /lrepo a flat folder with
# build 15's images and headers. Everything is installed with --no-install-recommends, so dkms's Recommends (gcc) never comes;
# the headers' Depends brings gcc-N-for-host. openssl is installed by name: DKMS signs with it, and every real system has it
# (ca-certificates depends on it); without it the modules stay unsigned.
# MODE=wheels: the wheel drivers (hid-fanatecff, hid-tmff2, new-lg4ff) and xpadneo, the system with no NVIDIA package: no plain
#              gcc is ever installed.
# MODE=all:    the same plus NVIDIA's open modules. nvidia-kernel-open-dkms-stereo3d Depends on g++, which brings gcc, so before
#              the kernel arrives the gcc and cc commands are diverted away (dpkg-divert --rename): DKMS then builds all five for
#              RELEASE, in the install ORDER image-first or headers-first, with whatever compiler the headers name.
# EXPECT=green: every module is built, signed, with the release's vermagic, and no make.log says "gcc: not found".
# EXPECT=red (the published 14.2 headers): DKMS fails, and its make logs say "gcc: not found".
set -uo pipefail
REL=$1; ORDER=$2; EXPECT=$3; MODE=$4
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
NR="--no-install-recommends"
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf 'Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n' > /etc/apt/sources.list.d/sparky.sources
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky
apt-get -y update >/dev/null 2>&1
apt-get -y $NR install apt-utils >/dev/null 2>&1
mkdir -p /stub/a/DEBIAN /stub/b/DEBIAN /flat
printf 'Package: firmware-nvidia-gsp\nVersion: 615.71.09-2\nArchitecture: amd64\nMaintainer: Stub\nDescription: EMPTY STUB for this test: the real package comes from NVIDIA repository, not from the edition repo\n' > /stub/a/DEBIAN/control
printf 'Package: nvidia-installer-cleanup\nVersion: 1\nArchitecture: amd64\nMaintainer: Stub\nDescription: EMPTY STUB for this test (NVIDIA repository package)\n' > /stub/b/DEBIAN/control
dpkg-deb -b /stub/a /flat/firmware-nvidia-gsp_615.71.09-2_amd64.deb >/dev/null; dpkg-deb -b /stub/b /flat/nvidia-installer-cleanup_1_amd64.deb >/dev/null
cp /lrepo/*.deb /flat/ 2>/dev/null; rm -f /flat/*-lc-hr_*
(cd /flat && apt-ftparchive packages . > Packages)
echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/flat.list
printf 'Package: linux-image-* linux-headers-*\nPin: origin ""\nPin-Priority: 1002\n' > /etc/apt/preferences.d/flat
apt-get -y update >/dev/null 2>&1
echo "== $REL $ORDER $EXPECT $MODE"
echo "== candidate versions"; apt-cache policy linux-image-$REL linux-headers-$REL | grep -E "^linux|Candidate"
quiet() { grep -E "Autoinstall|rror|succeeded|Setting up (linux|nvidia|hid|new-lg4ff|xpadneo|dkms|gcc|g\+\+)|gcc: not found|Signing|E: |W: " | cut -c1-240; }
echo "== module sources (no Recommends)"
apt-get -y $NR install dkms openssl hid-fanatecff-dkms hid-tmff2-dkms new-lg4ff-dkms xpadneo-dkms 2>&1 | quiet
want=4
if [ "$MODE" = all ]; then
	want=5
	apt-get -y $NR install sparky-stereo-nvidia-driver-lock 2>&1 | quiet
	apt-get -y $NR install nvidia-kernel-open-dkms-stereo3d 2>&1 | quiet
	echo "== after NVIDIA's package: gcc $(command -v gcc || echo none), from $(dpkg-query -W -f='${Package} ${Version}' gcc 2>/dev/null)"
	for c in /usr/bin/gcc /usr/bin/cc; do dpkg-divert --local --rename --divert "$c.hidden-by-proof" --add "$c" >/dev/null; done
fi
echo "== before the kernel: plain gcc command: $(command -v gcc || echo none); cc: $(command -v cc || echo none)"
case $ORDER in
 image-first)
   apt-get -y $NR install linux-image-$REL 2>&1 | quiet; echo "image install exit ${PIPESTATUS[0]}"
   apt-get -y $NR install linux-headers-$REL 2>&1 | quiet; echo "headers install exit ${PIPESTATUS[0]}";;
 headers-first)
   apt-get -y $NR install linux-headers-$REL 2>&1 | quiet; echo "headers install exit ${PIPESTATUS[0]}"
   apt-get -y $NR install linux-image-$REL 2>&1 | quiet; echo "image install exit ${PIPESTATUS[0]}";;
esac
echo "== after the kernel: plain gcc command: $(command -v gcc || echo none); cc: $(command -v cc || echo none)"
echo "== compilers installed: $(dpkg-query -W -f='${Package} ${Version}; ' 'gcc' 'g++' 'gcc-16' 'gcc-*-for-host' 'gcc-16-x86-64-linux-gnu' 2>/dev/null)"
echo "== headers Depends: $(dpkg-query -W -f='${Depends}' linux-headers-$REL)"
echo "== .kernelvariables: $(tr '\n' '|' < /usr/src/linux-headers-$REL/.kernelvariables 2>/dev/null || echo absent)"
echo "== module sources: $(dpkg-query -W -f='${Package} ${Version}; ' nvidia-kernel-open-dkms-stereo3d xpadneo-dkms hid-fanatecff-dkms hid-tmff2-dkms new-lg4ff-dkms 2>/dev/null)"
echo "== dkms status"; dkms status 2>&1
echo "== modules"; find /lib/modules/$REL/updates -name '*.ko*' 2>/dev/null | sort | while read -r f; do echo "$f signer=$(modinfo -F signer $f) vermagic=$(modinfo -F vermagic $f | cut -d' ' -f1)"; done
logs=$(ls /var/lib/dkms/*/*/build/make.log /var/lib/dkms/*/*/log/make.log 2>/dev/null)
nf=$(grep -l 'gcc: not found' $logs 2>/dev/null | wc -l)
echo "== make logs saying gcc: not found: $nf of $(echo $logs | wc -w)"
echo "== compilers named in the make logs: $(grep -ho 'x86_64-linux-gnu-gcc[-0-9]*\|[^-a-z/]gcc: not found' $logs 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
audit=$(dpkg --audit); echo "dpkg --audit lines $(printf '%s' "$audit" | grep -c .)"; [ -n "$audit" ] && echo "$audit" | head -5
n=$(find /lib/modules/$REL/updates -name '*.ko*' 2>/dev/null | wc -l)
signed=$(find /lib/modules/$REL/updates -name '*.ko*' 2>/dev/null | while read -r f; do [ -n "$(modinfo -F signer $f)" ] && echo s; done | wc -l)
installed=$(dkms status 2>/dev/null | grep -c ", $REL, x86_64: installed")
if [ "$EXPECT" = green ]; then
	ok=1
	command -v gcc >/dev/null && { echo "FAIL: a plain gcc command is present"; ok=0; }
	[ "$installed" -ge $want ] || { echo "FAIL: $installed DKMS modules installed for $REL, want $want"; ok=0; }
	[ "$nf" = 0 ] || { echo "FAIL: gcc: not found"; ok=0; }
	[ "$signed" = "$n" ] && [ "$n" -gt 0 ] || { echo "FAIL: $signed of $n module files signed"; ok=0; }
	[ -z "$audit" ] || { echo "FAIL: dpkg --audit not empty"; ok=0; }
	[ $ok = 1 ] && echo "PASS green: $installed DKMS modules installed for $REL ($MODE), $n module files, all signed, no gcc command" || exit 1
else
	command -v gcc >/dev/null && { echo "FAIL red: a plain gcc command is present, the control proves nothing"; exit 1; }
	[ "$installed" = 0 ] && [ "$nf" -gt 0 ] && echo "PASS red: 0 of $want DKMS modules installed for $REL ($MODE); $nf make logs say gcc: not found" || { echo "FAIL red: $installed installed, $nf gcc: not found"; exit 1; }
fi
