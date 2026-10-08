#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The pin of sparky-stereo-ffmpeg-fdk alone, without a build: stand-in packages (ffmpeg and libavcodec63, amd64 and i386, a
# local +fdk1 build installed, the edition's newer +stereo3d3 in a repository with the edition's origin and its pin file),
# the real helper package installed, upgraded around and removed. The cases, each a check that can fail:
#   a pin with a "*" at the start of the version (the first version of this package shipped one) ... apt accepts it and keeps nothing
#   the helper installed while its build is on the computer .... the postinst writes the pin: exact version, name:arch entries;
#                                                                  the candidate of every package, the 32-bit twin too, is the
#                                                                  local build; full-upgrade changes nothing; no warning
#   the helper removed ......................................... the pin goes, the notice is printed, apt wants the edition's FFmpeg
#   installed again ............................................ the pin is back
#   the state names a version that is not installed ............ no pin is written
#   purged ..................................................... the state and the pin are gone
#   write_pin with an architecture "all" entry and with none ... the name alone; nothing written
# Usage: test-pin.sh   (on the host: builds the helper, runs one container with one processor; T=work folder, IMAGE=the proof
#        base image; seconds)
# Last update 2026/10/08
if [ "${INSIDE:-0}" != 1 ]; then
	set -euo pipefail
	HERE=$(cd "$(dirname "$0")" && pwd)
	T=${T:-/mnt/build/mdmo2/fdktest}
	IMAGE=${IMAGE:-mdmo-proofbase:1}
	PINS=${PINS:-$HERE/../../../apt}
	mkdir -p "$T/pinpkgs"
	rm -f "$T"/pinpkgs/*.deb
	if [ -n "${PREBUILT:-}" ]; then cp "$PREBUILT" "$T/pinpkgs/"; else OUT="$T/pinpkgs" "$HERE/../build.sh" >/dev/null; fi
	exec docker run --rm --name "${NAME:-sparky-fdk-pintest}" --platform linux/amd64 --cpus 1 \
		-v "$T/pinpkgs:/pkgs:ro" -v "$PINS:/pins:ro" -v "$HERE/..:/g:ro" -e INSIDE=1 "$IMAGE" bash /g/tests/test-pin.sh
fi

export DEBIAN_FRONTEND=noninteractive LC_ALL=C
PASS=0
FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }

PIN=/etc/apt/preferences.d/sparky-stereo-ffmpeg-fdk
STATE=/var/lib/sparky-stereo-ffmpeg-fdk
BASE=10:9.0.2-dmo1+stereo3d2
NEW=10:9.0.2-dmo1+stereo3d3
LOC=$BASE+fdk1

mk() { # name version arch dir
	local d
	d=$(mktemp -d)
	mkdir -p "$d/DEBIAN"
	printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMulti-Arch: same\nMaintainer: t <t@example.org>\nDescription: stand-in\n' "$1" "$2" "$3" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$4/$1_${2//:/%3a}_$3.deb" >/dev/null
	rm -rf "$d"
}
cand() { apt-cache policy "$1" | awk '/Candidate:/{print $2}'; }
inst_lines() { apt-get -s full-upgrade 2>&1 | grep -c -E '^(Inst|Remv) (ffmpeg|libavcodec63)'; }

# the edition's repository (origin and pin as in git), the local build installed
rm -f /etc/apt/sources.list.d/* /etc/apt/sources.list
dpkg --add-architecture i386
mkdir -p /t/repo /t/local
for a in amd64 i386; do
	mk libavcodec63 "$BASE" $a /t/repo
	mk libavcodec63 "$NEW" $a /t/repo
	mk libavcodec63 "$LOC" $a /t/local
done
mk ffmpeg "$BASE" amd64 /t/repo
mk ffmpeg "$NEW" amd64 /t/repo
mk ffmpeg "$LOC" amd64 /t/local
(
	cd /t/repo || exit 1
	dpkg-scanpackages --multiversion . >Packages 2>/dev/null
	apt-ftparchive release . >Release.body 2>/dev/null
	{ printf 'Origin: Sparky Stereo OS\nLabel: Sparky Stereo OS\nSuite: x\nCodename: x\n'; cat Release.body; } >Release
)
check "the stand-in repository has the edition's origin (the pin file of git keys on it)" grep -q '^Origin: Sparky Stereo OS' /t/repo/Release
echo 'deb [trusted=yes] file:/t/repo ./' >/etc/apt/sources.list.d/t.list
cp /pins/sparky-stereo /etc/apt/preferences.d/
apt-get update -qq >/dev/null 2>&1
dpkg -i /t/local/*.deb >/dev/null 2>&1
eq "the stand-in local build is installed (ffmpeg)" "$(dpkg-query -W -f='${Version}' ffmpeg)" "$LOC"
eq "... and libavcodec63:i386" "$(dpkg-query -W -f='${Version}' libavcodec63:i386)" "$LOC"
mkdir -p $STATE
printf "LOCAL_BASE='%s'\nLOCAL_VERSION='%s'\nLOCAL_USER='tester'\nLOCAL_PACKAGES='ffmpeg:amd64 libavcodec63:amd64 libavcodec63:i386'\nBUILT_AT='today'\n" "$BASE" "$LOC" >$STATE/installed

echo "=== the control: no pin, and the pin of the first version (a * at the start)"
eq "without a pin the edition's newer FFmpeg is the candidate" "$(cand ffmpeg)" "$NEW"
check "... and a full-upgrade would replace the local build" test "$(inst_lines)" -gt 0
printf 'Package: ffmpeg libavcodec63\nPin: version *+fdk*\nPin-Priority: 1002\n' >$PIN
eq "a version pin with a leading * is accepted without a warning" "$(apt-cache policy ffmpeg 2>&1 | grep -c -E '^(W|E):')" 0
eq "... and keeps nothing (the candidate is still the edition's)" "$(cand ffmpeg)" "$NEW"
printf 'Package: ffmpeg libavcodec63\nPin: version 10:9.0.2-dmo1+stereo3d2+fdk*\nPin-Priority: 1002\n' >$PIN
eq "a version pin with a trailing * keeps the native-architecture build" "$(cand ffmpeg)" "$LOC"
eq "... but a name alone leaves the 32-bit twin to the edition" "$(cand libavcodec63:i386)" "$NEW"
rm -f $PIN

echo "=== the helper is installed while its build is on the computer"
dpkg -i --force-depends /pkgs/sparky-stereo-ffmpeg-fdk_*.deb >/tmp/dpkg1.log 2>&1 || tail -5 /tmp/dpkg1.log
check "the package is installed" dpkg -s sparky-stereo-ffmpeg-fdk
check "the pin file was written by the postinst" test -s $PIN
eq "the pin names the exact version" "$(grep -c -x "Pin: version $LOC" $PIN)" 1
eq "the pin has no pattern in its version" "$(grep -c -E '^Pin: version .*\*' $PIN)" 0
eq "the pin has priority 1002" "$(grep -c -x 'Pin-Priority: 1002' $PIN)" 1
check "the pin names the 32-bit twin with its architecture" grep -q -E '^Package:.* libavcodec63:i386( |$)' $PIN
eq "apt reads the pin without a warning" "$(apt-cache policy ffmpeg libavcodec63 libavcodec63:i386 2>&1 | grep -c -E '^(W|E|N):')" 0
eq "ffmpeg: the candidate is the local build" "$(cand ffmpeg)" "$LOC"
eq "libavcodec63: the candidate is the local build" "$(cand libavcodec63)" "$LOC"
eq "libavcodec63:i386: the candidate is the local build" "$(cand libavcodec63:i386)" "$LOC"
eq "the installed local version has priority 1002" "$(apt-cache policy ffmpeg | awk -v v="$LOC" '$1=="***" && $2==v {print $3}')" 1002
eq "the edition's newer version stays at the repository's 1001" "$(apt-cache policy ffmpeg | awk -v v="$NEW" '$1==v {print $2}')" 1001
eq "full-upgrade changes nothing about FFmpeg" "$(inst_lines)" 0
eq "the package ships no pin file of its own" "$(dpkg -L sparky-stereo-ffmpeg-fdk | grep -c preferences.d/sparky-stereo-ffmpeg-fdk)" 0

echo "=== the helper is removed; the local build stays"
out=$(dpkg -r sparky-stereo-ffmpeg-fdk 2>&1)
check "the notice says the FFmpeg built here is still installed" grep -q 'still installed' <<<"$out"
check "the pin is gone" test ! -e $PIN
check "the state is kept (the notice says how to go back)" test -s $STATE/installed
eq "the local build is still installed" "$(dpkg-query -W -f='${Version}' ffmpeg)" "$LOC"
eq "apt's candidate is the edition's again" "$(cand ffmpeg)" "$NEW"
check "a full-upgrade would put the edition's FFmpeg back (as the notice says)" test "$(inst_lines)" -gt 0

echo "=== the helper is installed again: the pin comes back"
dpkg -i --force-depends /pkgs/sparky-stereo-ffmpeg-fdk_*.deb >/tmp/dpkg2.log 2>&1 || tail -5 /tmp/dpkg2.log
check "the pin is back" test -s $PIN
eq "ffmpeg: the candidate is the local build" "$(cand ffmpeg)" "$LOC"
eq "libavcodec63:i386: the candidate is the local build" "$(cand libavcodec63:i386)" "$LOC"
eq "full-upgrade changes nothing about FFmpeg" "$(inst_lines)" 0

echo "=== the state names a build that is not installed: no pin"
dpkg -r sparky-stereo-ffmpeg-fdk >/dev/null 2>&1
sed -i "s/^LOCAL_VERSION=.*/LOCAL_VERSION='$BASE+fdk2'/" $STATE/installed
dpkg -i --force-depends /pkgs/sparky-stereo-ffmpeg-fdk_*.deb >/tmp/dpkg3.log 2>&1 || tail -5 /tmp/dpkg3.log
check "no pin is written for a version that is not installed" test ! -e $PIN

echo "=== purge"
sed -i "s/^LOCAL_VERSION=.*/LOCAL_VERSION='$LOC'/" $STATE/installed
dpkg -i --force-depends /pkgs/sparky-stereo-ffmpeg-fdk_*.deb >/dev/null 2>&1
check "(the pin is there before the purge)" test -s $PIN
dpkg -P sparky-stereo-ffmpeg-fdk >/dev/null 2>&1
check "the pin is gone" test ! -e $PIN
check "the state folder is gone" test ! -e $STATE
eq "the local build is still installed (purging the helper does not touch it)" "$(dpkg-query -W -f='${Version}' ffmpeg)" "$LOC"

echo "=== write_pin by itself"
export SPARKY_FDK_STATE=/tmp/st SPARKY_FDK_PINFILE=/tmp/pinout
mkdir -p /tmp/st
# shellcheck disable=SC1091
. /g/lib/common.sh
printf "LOCAL_BASE='%s'\nLOCAL_VERSION='%s'\nLOCAL_USER='u'\nLOCAL_PACKAGES='ffmpeg:amd64 ffmpeg-doc:all libavcodec63:amd64 libavcodec63:i386 libavcodec63:amd64'\n" "$BASE" "$LOC" >/tmp/st/installed
write_pin
eq "an architecture all entry is written as the name alone, and a duplicate once" "$(grep '^Package:' /tmp/pinout)" "Package: ffmpeg-doc ffmpeg:amd64 libavcodec63:amd64 libavcodec63:i386"
eq "the file is readable by everyone" "$(stat -c %a /tmp/pinout)" 644
eq "no temporary file is left in the state folder" "$(ls /tmp/st | grep -c '^pin\.')" 0
rm -f /tmp/pinout
printf "LOCAL_BASE='%s'\nLOCAL_VERSION='%s'\nLOCAL_USER='u'\nLOCAL_PACKAGES=''\n" "$BASE" "$LOC" >/tmp/st/installed
write_pin; rc=$?
eq "no packages: nothing is written (exit status not 0)" "$([ $rc -ne 0 ] && echo yes || echo no)" yes
check "... and no file" test ! -e /tmp/pinout
rm -f /tmp/st/installed /tmp/pinout
write_pin; rc=$?
eq "no state: nothing is written (exit status not 0)" "$([ $rc -ne 0 ] && echo yes || echo no)" yes
check "... and no file" test ! -e /tmp/pinout

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
