#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The upgrade from our Debian-based FFmpeg (the -extra libraries, 7:9.0.2-1+stereo3d2) to the edition's FFmpeg on
# deb-multimedia's packaging, in a debian:testing container with deb-multimedia (the media-on-dmo proof base): first
# the old set is installed from /old, then the repository /new (the new FFmpeg and these transitional packages, indexed
# by make-repo.sh) and the edition's pins are put in place, and a full-upgrade must hold nothing back and remove nothing
# of the FFmpeg family. Without the transitional packages apt wants to remove libavcodec-extra63, libavformat-extra63
# and libavfilter-extra12 (the first test of this folder's lane, 2026-10-08).
# Usage: docker run --rm --cpus 2 [-e SCENARIO=A] -v OLD:/old:ro -v NEW:/new:ro -v ../../apt:/pins:ro -v THIS:/t:ro mdmo-proofbase:1 /t/test-upgrade.sh
#   SCENARIO=A: the old computer has the normal libraries of our Debian-based build, not the -extra ones (default B: the -extra ones)
#   /new without the transitional packages is the control of scenario B that must fail
# Last update 2026/10/08
export DEBIAN_FRONTEND=noninteractive
PASS=0; FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
V=10:9.0.2-dmo1+stereo3d2
FAM='(ffmpeg|ffplay|libav(codec|device|filter|format|util)[0-9a-z-]*|libsw[a-z]+[0-9]*)'
sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
dpkg --add-architecture i386
apt-get update -qq 2>&1 | tail -1
echo "=== the old computer: our Debian-based FFmpeg ${SCENARIO:+(scenario $SCENARIO)}"
cd /old
if [ "${SCENARIO:-B}" = A ]; then
	# scenario A: the normal libraries of our Debian-based build, no -extra ones
	apt-get -y --no-install-recommends install ./ffmpeg_*_amd64.deb ./libavcodec63_*_amd64.deb ./libavcodec63_*_i386.deb ./libavformat63_*_amd64.deb ./libavformat63_*_i386.deb \
		./libavfilter12_*_amd64.deb ./libavfilter12_*_i386.deb ./libavdevice63_*_amd64.deb ./libavutil61_*_amd64.deb ./libavutil61_*_i386.deb \
		./libswresample7_*_amd64.deb ./libswresample7_*_i386.deb ./libswscale10_*_amd64.deb ./libswscale10_*_i386.deb >/tmp/old.log 2>&1 || tail -8 /tmp/old.log
else
apt-get -y --no-install-recommends install ./ffmpeg_*_amd64.deb ./libavcodec-extra63_*_amd64.deb ./libavcodec-extra63_*_i386.deb ./libavformat-extra63_*_amd64.deb ./libavformat-extra63_*_i386.deb \
	./libavfilter-extra12_*_amd64.deb ./libavfilter-extra12_*_i386.deb ./libavdevice63_*_amd64.deb ./libavutil61_*_amd64.deb ./libavutil61_*_i386.deb \
	./libswresample7_*_amd64.deb ./libswresample7_*_i386.deb ./libswscale10_*_amd64.deb ./libswscale10_*_i386.deb ./libavcodec-extra_*_amd64.deb ./libavformat-extra_*_amd64.deb ./libavfilter-extra_*_amd64.deb >/tmp/old.log 2>&1 || tail -8 /tmp/old.log
fi
dpkg -l | awk -v re="^$FAM(:.*)?\$" '/^ii/ && $2 ~ re {print $2, $3}' | tee /tmp/before.txt
if [ "${SCENARIO:-B}" = A ]; then
	eq "the old libavcodec63 is installed" "$(dpkg-query -W -f='${Version}' libavcodec63:amd64)" "7:9.0.2-1+stereo3d2"
else
	eq "the old libavcodec-extra63 is installed" "$(dpkg-query -W -f='${Version}' libavcodec-extra63:amd64)" "7:9.0.2-1+stereo3d2"
fi
cp /pins/sparky-stereo /etc/apt/preferences.d/
names=$(awk '/^Package: /{print $2}' /new/Packages | sort -u | tr '\n' ' ')
{ for o in Debian 'Unofficial Multimedia Packages'; do printf 'Package: %s\nPin: release o=%s\nPin-Priority: -1\n\n' "$names" "$o"; done; } >/etc/apt/preferences.d/sparky-stereo-only-ours
echo 'deb [trusted=yes] file:/new ./' >/etc/apt/sources.list.d/sparky-stereo-test.list
apt-get update -qq 2>&1 | tail -1
echo "=== apt-get -s full-upgrade"
apt-get -s full-upgrade >/tmp/sim.txt 2>&1
grep -E "^(E:|[0-9]+ upgraded)|^The following packages (have been kept back|will be REMOVED)" -A3 /tmp/sim.txt | head -20 | cut -c1-160
eq "nothing of the FFmpeg family is removed" "$(grep -c -E "^Remv $FAM" /tmp/sim.txt)" 0
eq "nothing of the FFmpeg family is held back" "$(sed -n '/have been kept back/,/^[0-9]/p' /tmp/sim.txt | grep -c -E "$FAM")" 0
echo "=== apt-get full-upgrade"
apt-get -y full-upgrade >/tmp/up.log 2>&1; rc=$?
tail -3 /tmp/up.log | cut -c1-160
eq "full-upgrade exits 0" "$rc" 0
dpkg -l | awk -v re="^$FAM(:.*)?\$" '/^ii/ && $2 ~ re {print $2, $3}' | tee /tmp/after.txt
eq "ffmpeg is the edition's build" "$(dpkg-query -W -f='${Version}' ffmpeg)" "$V"
eq "libavcodec63:amd64 is the edition's build" "$(dpkg-query -W -f='${Version}' libavcodec63:amd64)" "$V"
eq "libavformat63:i386 is the edition's build" "$(dpkg-query -W -f='${Version}' libavformat63:i386 2>/dev/null)" "$V"
if [ "${SCENARIO:-B}" != A ]; then
	eq "libavcodec-extra63 is the transitional package now" "$(dpkg-query -W -f='${Version}' libavcodec-extra63:amd64)" "$V"
	eq "libavcodec-extra63:i386 too" "$(dpkg-query -W -f='${Version}' libavcodec-extra63:i386)" "$V"
fi
eq "apt-get check finds nothing broken" "$(apt-get check 2>&1 | grep -c -E '^E:')" 0
eq "dpkg --audit finds nothing" "$(dpkg --audit | wc -l)" 0
eq "ffmpeg runs and has the native aac, no libfdk_aac" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c -E ' (aac|libfdk_aac) ' )" 1
eq "the transitional packages are empty (no library file)" "$(dpkg -L libavcodec-extra63:amd64 | grep -c '\.so')" 0
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
