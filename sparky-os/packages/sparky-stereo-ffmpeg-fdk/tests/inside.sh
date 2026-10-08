#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The end-to-end test of sparky-stereo-ffmpeg-fdk, inside a debian:testing container (root) that has deb-multimedia
# configured (the proof base of the media-on-dmo lane: dmo-setup.sh), with the test repositories of make-test-repos.sh
# mounted at /repo2, /repo2-no386 and /repo3, the helper and a stand-in for sparky-stereo-apt in /pkgs, the edition's pins
# in /pins and this folder in /tests. Run it with run-tests.sh. I386=1 adds the 32-bit libraries to the computer.
# What it proves, each with a check that can fail:
#   1. the edition's FFmpeg has no libfdk_aac; the helper does nothing until asked; declining the question changes nothing
#   2. without a source index, or with a missing 32-bit package, the helper stops before it changes anything
#   3. the build: libfdk_aac is listed, an AAC file is encoded (HE-AAC, which the native encoder cannot), apt keeps the build
#      (the build wrote the pin: exact version, candidate of every package, the 32-bit twin too, is the local build, full-upgrade
#      does nothing), the build tools are gone again, the 32-bit libraries are in step (I386=1)
#   4. an update of the edition's FFmpeg: apt update starts the rebuild by itself (and apt keeps the old local build while it
#      runs), the pin follows the new local build, which has the encoder
#   5. --remove: the edition's FFmpeg is back, the encoder and the pin are gone
# Last update 2026/10/08
export DEBIAN_FRONTEND=noninteractive
PASS=0
FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
check() { # description command...
	local d=$1
	shift
	if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi
}
eq() { # description actual expected
	if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi
}
V2=10:9.0.2-dmo1+stereo3d2
V3=10:9.0.2-dmo1+stereo3d3
STATE=/var/lib/sparky-stereo-ffmpeg-fdk
HELPER=sparky-stereo-ffmpeg-fdk
installed_count() { dpkg -l | grep -c '^ii'; }
# the Debian mirrors are a CDN that is sometimes between two states: once more after a new update, never more
apt_retry() { apt-get "$@" || { apt-get update -qq >/dev/null 2>&1; apt-get "$@"; }; }
ver() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null; }
wait_idle() { # seconds: until no rebuild holds the lock and the state names the version $2
	local t=$1 want=$2 i
	for ((i = 0; i < t; i += 10)); do
		if ( flock -n 9 ) 9>/run/sparky-stereo-ffmpeg-fdk.lock 2>/dev/null && grep -q "LOCAL_BASE='$want'" $STATE/installed 2>/dev/null; then return 0; fi
		sleep 10
	done
	return 1
}

echo "=== setup"
sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
# the edition's pins: the one for the origin as it is in git; the "only ours" list as make-only-ours.py makes it, but for the
# test repository (the list of git is made for the whole repository, which has Mesa, KWin ... that this one does not)
cp /pins/sparky-stereo /etc/apt/preferences.d/
names=$(awk '/^Package: /{print $2}' /repo2/Packages /repo3/Packages | sort -u | tr '\n' ' ')
{
	echo "# the test repository's names, blocked from Debian and deb-multimedia as sparky-stereo-only-ours does"
	for o in Debian 'Unofficial Multimedia Packages'; do printf 'Package: %s\nPin: release o=%s\nPin-Priority: -1\n\n' "$names" "$o"; done
} >/etc/apt/preferences.d/sparky-stereo-only-ours
[ "${I386:-0}" = 1 ] && dpkg --add-architecture i386
printf 'deb [trusted=yes] file:/repo2 ./\ndeb-src [trusted=yes] file:/repo2 ./\n' >/etc/apt/sources.list.d/sparky-stereo-test.list
apt-get update -qq 2>&1 | tail -2
apt-get -y -qq install sudo util-linux python3 ca-certificates >/dev/null 2>&1
useradd -m -u 1000 -s /bin/bash tester
printf 'tester ALL=(ALL) NOPASSWD:ALL\nDefaults:tester env_keep += "SPARKY_FDK_TMPBASE"\n' >/etc/sudoers.d/tester
chmod 440 /etc/sudoers.d/tester
grep -q '^Origin: Sparky Stereo OS' /repo2/Release && ok "the test repository has the edition's origin"
check "the test repository has a source index with ffmpeg-dmo" grep -q '^Package: ffmpeg-dmo' /repo2/Sources

echo "=== 1. the edition's FFmpeg, without the encoder"
apt_retry -y --no-install-recommends install ffmpeg >/tmp/i1.log 2>&1 || tail -5 /tmp/i1.log
if [ "${I386:-0}" = 1 ]; then
	apt_retry -y --no-install-recommends install libavcodec63:i386 libavformat63:i386 libavutil61:i386 libswscale10:i386 libswresample7:i386 libavfilter12:i386 libavdevice63:i386 >/tmp/i2.log 2>&1 || tail -5 /tmp/i2.log
fi
eq "ffmpeg is the edition's build" "$(ver ffmpeg)" "$V2"
eq "libavcodec63:amd64 is the edition's build" "$(dpkg-query -W -f='${Version}' libavcodec63:amd64)" "$V2"
[ "${I386:-0}" = 1 ] && eq "libavcodec63:i386 is the edition's build" "$(dpkg-query -W -f='${Version}' libavcodec63:i386)" "$V2"
eq "no libfdk_aac in the edition's FFmpeg" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c libfdk_aac)" 0
eq "the native aac encoder is there" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c -E '^ A[.A-Z]{5} aac ')" 1
eq "no libfdk-aac package installed yet" "$(dpkg -l | grep -c -E '^ii +libfdk')" 0

echo "=== 2. the helper is installed; nothing is built by installing it"
apt-get -y install /pkgs/sparky-stereo-apt-standin_*.deb /pkgs/sparky-stereo-ffmpeg-fdk_*.deb >/tmp/i3.log 2>&1 || tail -8 /tmp/i3.log
check "the helper is installed" dpkg -s $HELPER
PIN=/etc/apt/preferences.d/sparky-stereo-ffmpeg-fdk
check "no pin file before a build exists (each build writes its own)" test ! -e $PIN
check "the hook file is installed" test -f /etc/apt/apt.conf.d/99sparky-stereo-ffmpeg-fdk
check "the source line file is installed" test -f /etc/apt/sources.list.d/sparky-stereo-ffmpeg-src.sources
eq "apt prints no warning about the package's files" "$(apt-cache policy ffmpeg 2>&1 | grep -c -E '^(W|E):')" 0
rm -f /etc/apt/sources.list.d/sparky-stereo-ffmpeg-src.sources     # its URL is the real repository; the test has its own deb-src
hook_out=$(apt-get update 2>&1 | grep -c -i 'Sparky Stereo OS:')
eq "apt update says nothing about FFmpeg when no local build exists" "$hook_out" 0
eq "nothing installed by the helper's presence" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c libfdk_aac)" 0
st=$(runuser -u tester -- $HELPER --status 2>&1)
check "--status says that no local build is installed" grep -q 'No local build' <<<"$st"
check "--status shows the edition's version" grep -q "$V2" <<<"$st"
before=$(installed_count)

if [ "${FAST:-0}" != 1 ]; then
if [ "${ONLY_4D:-0}" != 1 ]; then
echo "=== 3. the question: not a terminal, then a terminal and no"
out=$(runuser -u tester -- $HELPER </dev/null 2>&1); rc=$?
check "without a terminal and without --yes it stops (exit $rc)" test "$rc" -ne 0
check "... and says why" grep -q 'needs a terminal' <<<"$out"
out=$(printf 'n\n' | script -qec "runuser -u tester -- $HELPER" /dev/null 2>&1 | tr -d '\r')
check "the warning says the result is for THIS computer only" grep -q 'THIS computer only' <<<"$out"
check "the warning says it may not be passed on" grep -q 'may not pass it on' <<<"$out"
check "the warning says how long it takes (minutes)" grep -q -E 'takes about [0-9]+ to [0-9]+ minutes' <<<"$out"
check "the warning names LICENSE.md" grep -q 'LICENSE.md' <<<"$out"
check "answering no ends with 'Nothing was done.'" grep -q 'Nothing was done' <<<"$out"
eq "answering no installed nothing" "$(installed_count)" "$before"
check "answering no left no state" test ! -e $STATE/installed
check "answering no left no consent" test ! -e $STATE/consent
echo "$out" | sed -n 1,16p
eq "the usage in Polish (LANG=pl_PL.UTF-8)" "$(LANG=pl_PL.UTF-8 runuser -u tester -- env LANG=pl_PL.UTF-8 $HELPER --help | head -n1)" "Użycie: sparky-stereo-ffmpeg-fdk [opcja]"
eq "the usage in Brazilian Portuguese (LANG=pt_BR.UTF-8)" "$(runuser -u tester -- env LANG=pt_BR.UTF-8 $HELPER --help | head -n1)" "Uso: sparky-stereo-ffmpeg-fdk [opção]"
eq "the usage falls back to English (LANG=ja_JP.UTF-8)" "$(runuser -u tester -- env LANG=ja_JP.UTF-8 $HELPER --help | head -n1)" "Usage: sparky-stereo-ffmpeg-fdk [option]"

echo "=== 4. it stops before it changes anything"
printf 'deb [trusted=yes] file:/repo2 ./\n' >/etc/apt/sources.list.d/sparky-stereo-test.list
apt-get update -qq >/dev/null 2>&1
out=$(runuser -u tester -- $HELPER --yes 2>&1); rc=$?
check "without the source line in apt's sources it is refused (exit $rc)" test "$rc" -ne 0
check "... with the message about the source package" grep -q 'no source package' <<<"$out"
eq "... and nothing installed" "$(installed_count)" "$before"
printf 'deb [trusted=yes] file:/repo2 ./\ndeb-src [trusted=yes] file:/repo2 ./\n' >/etc/apt/sources.list.d/sparky-stereo-test.list
apt-get update -qq >/dev/null 2>&1
if [ "${I386:-0}" = 1 ]; then
	printf 'deb [trusted=yes] file:/repo2-no386 ./\ndeb-src [trusted=yes] file:/repo2-no386 ./\n' >/etc/apt/sources.list.d/sparky-stereo-test.list
	apt-get update -qq >/dev/null 2>&1
	out=$(runuser -u tester -- $HELPER --yes 2>&1); rc=$?
	check "a 32-bit package the repository does not have stops it (exit $rc)" test "$rc" -ne 0
	check "... with the message about the 32-bit package" grep -q '32-bit package' <<<"$out"
	eq "... before any build tool was installed" "$(installed_count)" "$before"
	check "... and no build directory is left" test -z "$(ls /var/tmp | grep sparky-stereo-ffmpeg-fdk)"
	printf 'deb [trusted=yes] file:/repo2 ./\ndeb-src [trusted=yes] file:/repo2 ./\n' >/etc/apt/sources.list.d/sparky-stereo-test.list
	apt-get update -qq >/dev/null 2>&1
fi

echo "=== 4b. no room: it stops before any build tool is installed"
mkdir -p /mnt/small/b && chown tester /mnt/small/b
out=$(SPARKY_FDK_TMPBASE=/mnt/small/b runuser -u tester -- env SPARKY_FDK_TMPBASE=/mnt/small/b $HELPER --yes 2>&1); rc=$?
check "a folder with too little room is refused (exit $rc)" test "$rc" -ne 0
check "... with the message about the room" grep -q 'Not enough room' <<<"$out"
eq "... and nothing installed" "$(installed_count)" "$before"

echo "=== 4c. a build that fails changes nothing, and the build tools go again"
mkdir -p /mnt/noexec/b && chown tester /mnt/noexec/b
out=$(SPARKY_FDK_TMPBASE=/mnt/noexec/b runuser -u tester -- env SPARKY_FDK_TMPBASE=/mnt/noexec/b $HELPER --yes 2>&1); rc=$?
echo "$out" | tail -n 6 | cut -c1-200
check "a build that cannot run (no exec in its folder) stops with an error (exit $rc)" test "$rc" -ne 0
check "... says nothing was changed" grep -q 'Nothing was changed' <<<"$out"
check "... the end of the build log is shown" grep -q 'dpkg-buildpackage' <<<"$out"
eq "... and the build tools it installed are gone again" "$(installed_count)" "$before"
check "... the log of the failed build is kept" test -s $STATE/last-build.log
check "... no local build is recorded" test ! -e $STATE/installed
check "... the edition's FFmpeg is untouched" test "$(ver ffmpeg)" = "$V2"
check "... no build directory is left" test -z "$(ls /mnt/noexec/b)"
rm -f $STATE/last-failure

fi   # not ONLY_4D
echo "=== 4d. apt's own question about the build tools: answering no stops everything"
out=$(python3 /tests/pty-answer.py "Build it now?=y" "Do you want to continue=n" -- runuser -u tester -- $HELPER 2>&1 | tr -d '\r')
echo "$out" | grep -E "Do you want to continue|Abort|could not be installed|Nothing was changed" | cut -c1-160
check "apt asked its question (the build tools are listed and confirmed by the user)" grep -q 'Do you want to continue' <<<"$out"
check "answering no ends with the helper's message" grep -q 'could not be installed' <<<"$out"
eq "... and nothing installed" "$(installed_count)" "$before"
rm -f $STATE/last-failure $STATE/consent
if [ "${STOP_AFTER_4D:-0}" = 1 ]; then echo "SUMMARY pass=$PASS fail=$FAIL"; [ "$FAIL" -eq 0 ]; exit; fi

fi   # FAST
echo "=== 5. the build"
date -u +"build start %F %T"
runuser -u tester -- $HELPER --yes >/tmp/run1.log 2>&1; rc=$?
date -u +"build end %F %T"
tail -n 25 /tmp/run1.log | cut -c1-200
eq "the helper exits 0" "$rc" 0
L2=$V2+fdk1
eq "ffmpeg is the local build" "$(ver ffmpeg)" "$L2"
eq "libavcodec63 is the local build" "$(dpkg-query -W -f='${Version}' libavcodec63:amd64)" "$L2"
eq "libavutil61 is the local build" "$(dpkg-query -W -f='${Version}' libavutil61:amd64)" "$L2"
eq "ffmpeg -encoders lists libfdk_aac" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c libfdk_aac)" 1
eq "the native aac encoder is still there" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c -E '^ A[.A-Z]{5} aac ')" 1
ffmpeg -L 2>/dev/null | head -3
eq "ffmpeg -L says the local build is not legally redistributable" "$(ffmpeg -L 2>/dev/null | grep -c 'not legally redistributable')" 1
cd /tmp && ffmpeg -v error -y -f lavfi -i sine=frequency=440:duration=3 -c:a libfdk_aac -b:a 128k fdk.m4a
eq "an AAC file was encoded with libfdk_aac (codec)" "$(ffprobe -v error -show_entries stream=codec_name -of default=nw=1:nk=1 fdk.m4a)" aac
ffmpeg -v error -y -f lavfi -i sine=frequency=440:duration=3 -c:a libfdk_aac -profile:a aac_he -b:a 64k he.m4a
eq "HE-AAC, which the native encoder cannot make, was encoded" "$(ffprobe -v error -show_entries stream=profile -of default=nw=1:nk=1 he.m4a)" "HE-AAC"
check "the native encoder cannot make HE-AAC (the control)" bash -c '! ffmpeg -v error -y -f lavfi -i sine=frequency=440:duration=1 -c:a aac -profile:a aac_he /tmp/x.m4a'
check "the local libavcodec has the libfdk-aac dependency" bash -c "dpkg -s libavcodec63:amd64 | grep -q 'libfdk-aac2'"
eq "the source of the local build says the edition's tracker" "$(dpkg-query -W -f='${Bugs}' ffmpeg)" "https://github.com/Sparky-OS/sparky-stereo-os/issues"
check "the changelog of the local build says it may not be passed on" bash -c "zcat /usr/share/doc/libavcodec63/changelog.Debian.gz | head -8 | grep -q 'may not be passed on'"
check "the build directory is gone" test -z "$(ls /var/tmp | grep sparky-stereo-ffmpeg-fdk)"
check "the stage folder is gone" test ! -e $STATE/stage
check "the state is written" grep -q "LOCAL_VERSION='$L2'" $STATE/installed
check "libfdk-aac-dev is gone again (a build tool)" bash -c '! dpkg -s libfdk-aac-dev 2>/dev/null | grep -q "Status: install ok installed"'
check "libx264-dev is gone again (a build tool)" bash -c '! dpkg -s libx264-dev 2>/dev/null | grep -q "Status: install ok installed"'
eq "the only new package is the encoder's runtime library" "$(( $(installed_count) - before ))" 1
check "libfdk-aac2 is installed" bash -c "dpkg -s libfdk-aac2 | grep -q 'Status: install ok installed'"
check "the build wrote the pin file" test -s $PIN
eq "the pin names the exact local version" "$(grep -c -x "Pin: version $L2" $PIN)" 1
eq "the pin has no pattern in its version" "$(grep -c -E '^Pin: version .*\*' $PIN)" 0
eq "apt reads the pin file without a warning" "$(apt-cache policy ffmpeg libavcodec63 2>&1 | grep -c -E '^(W|E|N):')" 0
eq "the local build has apt priority 1002" "$(apt-cache policy ffmpeg | awk -v v="$L2" '$1=="***" && $2==v {print $3}')" 1002
eq "the edition's version keeps the repository's priority 1001" "$(apt-cache policy ffmpeg | awk -v v="$V2" '$1==v {print $2}')" 1001
eq "apt's candidate for ffmpeg is the local build" "$(apt-cache policy ffmpeg | awk '/Candidate:/{print $2}')" "$L2"
eq "apt's candidate for libavcodec63 is the local build" "$(apt-cache policy libavcodec63 | awk '/Candidate:/{print $2}')" "$L2"
[ "${I386:-0}" = 1 ] && eq "apt's candidate for libavcodec63:i386 is the local build" "$(apt-cache policy libavcodec63:i386 | awk '/Candidate:/{print $2}')" "$L2"
eq "full-upgrade changes nothing about FFmpeg (Inst/Remv lines)" "$(apt-get -s full-upgrade 2>&1 | grep -c -E '^(Inst|Remv) (ffmpeg|libav|libsw)')" 0
check "apt-get check finds nothing broken" apt-get check
if [ "${I386:-0}" = 1 ]; then
	eq "libavcodec63:i386 is in step with the local build" "$(dpkg-query -W -f='${Version}' libavcodec63:i386)" "$L2"
	eq "libavutil61:i386 is in step" "$(dpkg-query -W -f='${Version}' libavutil61:i386)" "$L2"
	eq "libswscale10:i386 is in step" "$(dpkg-query -W -f='${Version}' libswscale10:i386)" "$L2"
	# the 32-bit library is the edition's own file, not a rebuild
	mkdir -p /tmp/e386 && dpkg-deb -x /repo2/libavcodec63_9.0.2-dmo1+stereo3d2_i386.deb /tmp/e386
	eq "the 32-bit libavcodec is the edition's own file" "$(sha256sum /usr/lib/i386-linux-gnu/libavcodec.so.63.* | cut -c1-64)" "$(sha256sum /tmp/e386/usr/lib/i386-linux-gnu/libavcodec.so.63.* | cut -c1-64)"
	eq "dpkg --verify finds no file of the two architectures different from its package" "$(dpkg --verify libavcodec63:amd64 libavcodec63:i386 libavutil61:amd64 libavutil61:i386 2>&1 | wc -l)" 0
	check "dpkg --audit finds nothing" bash -c '[ -z "$(dpkg --audit)" ]'
fi

echo "=== 6. an update of the edition's FFmpeg starts the rebuild by itself"
printf 'deb [trusted=yes] file:/repo3 ./\ndeb-src [trusted=yes] file:/repo3 ./\n' >/etc/apt/sources.list.d/sparky-stereo-test.list
upd=$(apt-get update 2>&1 | grep 'Sparky Stereo OS:')
echo "apt update printed: $upd"
check "apt update announces the rebuild" grep -q "FFmpeg $V3" <<<"$upd"
eq "while the rebuild runs, apt's candidate is still the old local build" "$(apt-cache policy ffmpeg | awk '/Candidate:/{print $2}')" "$L2"
eq "... and full-upgrade changes nothing about FFmpeg" "$(apt-get -s full-upgrade 2>&1 | grep -c -E '^(Inst|Remv) (ffmpeg|libav|libsw)')" 0
check "the rebuild runs by itself and finishes" wait_idle 5400 "$V3"
tail -n 8 /var/log/sparky-stereo-ffmpeg-fdk.log | cut -c1-200
L3=$V3+fdk1
eq "ffmpeg is the new local build" "$(ver ffmpeg)" "$L3"
eq "libavcodec63 is the new local build" "$(dpkg-query -W -f='${Version}' libavcodec63:amd64)" "$L3"
eq "the pin follows the new build" "$(grep -c -x "Pin: version $L3" $PIN)" 1
eq "... and no longer names the old one" "$(grep -c -F "$L2" $PIN)" 0
eq "apt's candidate for ffmpeg is the new local build" "$(apt-cache policy ffmpeg | awk '/Candidate:/{print $2}')" "$L3"
[ "${I386:-0}" = 1 ] && eq "apt's candidate for libavcodec63:i386 is the new local build" "$(apt-cache policy libavcodec63:i386 | awk '/Candidate:/{print $2}')" "$L3"
eq "full-upgrade changes nothing about FFmpeg (new local build)" "$(apt-get -s full-upgrade 2>&1 | grep -c -E '^(Inst|Remv) (ffmpeg|libav|libsw)')" 0
eq "ffmpeg -encoders still lists libfdk_aac" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c libfdk_aac)" 1
[ "${I386:-0}" = 1 ] && eq "libavcodec63:i386 followed" "$(dpkg-query -W -f='${Version}' libavcodec63:i386)" "$L3"
check "the log says it was the automatic mode" grep -q 'mode automatic' /var/log/sparky-stereo-ffmpeg-fdk.log
check "no second rebuild is started by the next apt update" bash -c "! apt-get update 2>&1 | grep -q 'Sparky Stereo OS:'"
st=$(runuser -u tester -- $HELPER --status 2>&1)
check "--status shows the new local build" grep -q "$L3" <<<"$st"

echo "=== 7. back to the edition's FFmpeg"
out=$(runuser -u tester -- $HELPER --remove 2>&1); rc=$?
echo "$out" | tail -n 5 | cut -c1-200
eq "--remove exits 0" "$rc" 0
eq "ffmpeg is the edition's build again (the update's)" "$(ver ffmpeg)" "$V3"
eq "libavcodec63 is the edition's build again" "$(dpkg-query -W -f='${Version}' libavcodec63:amd64)" "$V3"
[ "${I386:-0}" = 1 ] && eq "libavcodec63:i386 is the edition's build again" "$(dpkg-query -W -f='${Version}' libavcodec63:i386)" "$V3"
eq "libfdk_aac is gone" "$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -c libfdk_aac)" 0
check "the state is cleared" test ! -e $STATE/installed
check "the pin file is gone" test ! -e $PIN
eq "apt's candidate for ffmpeg is the edition's build" "$(apt-cache policy ffmpeg | awk '/Candidate:/{print $2}')" "$V3"
check "the consent is cleared" test ! -e $STATE/consent
eq "full-upgrade has nothing to do for FFmpeg (Inst/Remv lines)" "$(apt-get -s full-upgrade 2>&1 | grep -c -E '^(Inst|Remv) (ffmpeg|libav|libsw)')" 0
check "apt-get check finds nothing broken" apt-get check

echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
