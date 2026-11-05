#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The apt hook (apt/99sparky-stereo-ffmpeg-fdk running lib/check-update) through the real apt-get update and apt update,
# in a disposable debian:testing container: the container's apt sources are put aside for a local flat repository with
# the edition's Origin and a Sources index (/tmp/repo, written here); the problems engine is the real one
# (sparky-stereo-problems installed); the command the hook would start is a stand-in that writes down its arguments.
# The cases:
#   no local build ............................ apt update succeeds, the hook says nothing, nothing started
#   local build older than the repository ..... the announcement, the stand-in called with --auto
#   the same on battery (on_ac_power says 1) .. the waiting message, nothing started
#   the same version as the repository ........ silence
#   a failed rebuild of that version .......... the message about the log, nothing started, no retry by itself
#   a rebuild already running (lock held) ..... silence, nothing started
#   a failure the engine keeps (no source record, no source line, an invalid record, the library missing): apt-get
#     update and apt update succeed, the failure's message is in their output, the problem is in the engine
#   a later successful check .................. the kept problem is cleared (the engine's note that no journal daemon
#     listens, in a container, is the one line allowed)
#   a failure nothing could keep (the engine's store broken, a clear that fails, the library missing with the engine
#     broken): apt-get update and apt update fail
# Usage: docker run --rm --cpus 1 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v BUILD-CHECKOUT/tools/https-only-apt.sh:/run/https-only-apt.sh:ro -v PACKAGE-FOLDER:/g:ro IMAGE bash /g/tests/test-hook.sh [/g | /usr]
#   (IMAGE: debian:testing with sparky-stereo-problems and python3 installed; /usr tests the installed package with its
#   own hook file in /etc/apt/apt.conf.d and its catalogs; for a package folder its hook file is installed with the
#   folder's path and its catalogs are generated)
# Last update 2026/11/02
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); a missing helper stops the script
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive
G=${1:-/g}
PASS=0; FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1: [$3] not in [$2]" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1: [$3] in [$2]" ;; *) ok "$1" ;; esac; }
for t in sparky-stereo-problems python3 flock apt-get apt; do
	command -v "$t" >/dev/null || { echo "needs $t" >&2; exit 2; }
done
[ "$(id -u)" -eq 0 ] || { echo "run it as root in a disposable container" >&2; exit 2; }
HOOK=/etc/apt/apt.conf.d/99sparky-stereo-ffmpeg-fdk
if [ "$G" = /usr ]; then
	LIB=/usr/lib/sparky-stereo-ffmpeg-fdk LANGD=/usr/share/sparky/sparky-stereo-ffmpeg-fdk
	[ -f "$HOOK" ] || { echo "the installed package has no $HOOK" >&2; exit 2; }
else
	LIB=$G/lib LANGD=$G/lang
	sed "s|/usr/lib/sparky-stereo-ffmpeg-fdk/check-update|$LIB/check-update|g" "$G/apt/99sparky-stereo-ffmpeg-fdk" >"$HOOK"
	mkdir -p /tmp/catalogs
	sparky-stereo-problems catalog sparky-stereo-ffmpeg-fdk "$LANGD" /tmp/catalogs --subject LOCAL10 >/dev/null || exit 2
	export SPARKY_STEREO_PROBLEMS_CATALOG=/tmp/catalogs:/usr/lib/systemd/catalog
fi
mkdir -p /tmp/apt-sources-aside
mv /etc/apt/sources.list.d/* /etc/apt/sources.list /tmp/apt-sources-aside/ 2>/dev/null
printf 'deb-src [trusted=yes] file:/tmp/repo ./\n' >/etc/apt/sources.list.d/hooktest.list
# another archive, as every computer has: apt runs Post-Invoke-Success only when some index was fetched
mkdir -p /tmp/other-repo
printf 'Package: hello\nBinary: hello\nVersion: 1\n\n' >/tmp/other-repo/Sources
printf 'Origin: Debian\nSuite: hooktest\nCodename: hooktest\nDate: %s\nSHA256:\n %s %s Sources\n' "$(date -Ru)" \
	"$(sha256sum </tmp/other-repo/Sources | cut -d' ' -f1)" "$(stat -c %s /tmp/other-repo/Sources)" >/tmp/other-repo/Release
chmod -R a+rX /tmp/other-repo
printf 'deb-src [trusted=yes] file:/tmp/other-repo ./\n' >/etc/apt/sources.list.d/other.list
export SPARKY_STEREO_ROOT=/tmp/engine LANG=en_US.UTF-8 LANGUAGE=en
export SPARKY_FDK_LIBDIR=$LIB SPARKY_FDK_LANGDIR=$LANGD SPARKY_FDK_STATE=/tmp/state SPARKY_FDK_LOCK=/tmp/lock
export SPARKY_FDK_BIN=/tmp/fakebin SPARKY_FDK_LOG=/tmp/fdk.log
mkdir -p /tmp/state /tmp/pathdir
printf '#!/bin/sh\necho "$@" >>/tmp/called\n' >/tmp/fakebin; chmod +x /tmp/fakebin
printf '#!/bin/sh\nexit 0\n' >/tmp/pathdir/on_ac_power; chmod +x /tmp/pathdir/on_ac_power
V=10:9.0.2-dmo1+stereo3d5
OLD=10:9.0.1-dmo1+stereo3d1
GOOD="Package: ffmpeg-dmo\nBinary: ffmpeg, libavcodec62\nVersion: $V\n\n"
OTHER="Package: something-else\nBinary: something-else\nVersion: 1\n\n"
INVALID="Package: ffmpeg-dmo\nBinary: ffmpeg\nVersion: not a version\n\n"
fixture() { # the repository's Sources index; a Release with the edition's Origin, as apt-get indextargets filters by it
	rm -rf /tmp/repo /var/lib/apt/lists/*_tmp_repo_*
	mkdir -p /tmp/repo
	printf '%b' "$1" >/tmp/repo/Sources
	{
		printf 'Origin: Sparky Stereo OS\nLabel: Sparky Stereo OS\nSuite: hooktest\nCodename: hooktest\nDate: %s\nSHA256:\n' "$(date -Ru)"
		printf ' %s %s Sources\n' "$(sha256sum </tmp/repo/Sources | cut -d' ' -f1)" "$(stat -c %s /tmp/repo/Sources)"
	} >/tmp/repo/Release
	chmod -R a+rX /tmp/repo
}
# apt-get update (apt update with APT=apt), VAR=value pairs given to the hook; sets out and rc
update() {
	rm -f /tmp/called
	out=$(env "$@" PATH="/tmp/pathdir:$PATH" "${APT:-apt-get}" update -qq 2>&1)
	rc=$?
	sleep 1
}
state() { # base version, failure marker
	rm -f /tmp/state/*; echo "accepted" >/tmp/state/consent
	[ -n "$1" ] && printf "LOCAL_BASE='%s'\nLOCAL_VERSION='%s+fdk1'\nLOCAL_USER='tester'\nLOCAL_PACKAGES='ffmpeg'\n" "$1" "$1" >/tmp/state/installed
	sparky-stereo-problems clear --all sparky-stereo-ffmpeg-fdk
	if [ -n "$2" ]; then
		details=$(python3 -c 'import json,sys; print(json.dumps({"data":{"version":sys.argv[1]}}))' "$2")
		sparky-stereo-problems keep --machine --quiet --details "$details" sparky-stereo-ffmpeg-fdk build LOCAL70 "$2" /tmp/build.log
	fi
	return 0
}
started() { if [ -e /tmp/called ]; then cat /tmp/called; else echo not-started; fi; }
problem() { sparky-stereo-problems text --machine sparky-stereo-ffmpeg-fdk update-check 2>/dev/null || echo no-problem; }
NOKEPT="Problem executing scripts APT::Update::Post-Invoke-Success"
# without a journal daemon (a container) the engine says so when it records an event, such as clearing a problem
quiet() {
	if [ -S /run/systemd/journal/socket ]; then printf '%s' "$1"; else printf '%s' "$1" | grep -v -F 'The system journal could not be reached'; fi
}

has "apt reads the hook" "$(apt-config dump | grep -F Post-Invoke-Success)" "$LIB/check-update"
fixture "$GOOD"
state "" ""; rm -f /tmp/state/consent
update; eq "no local build: apt-get update succeeds" "$rc" 0; eq "... the hook says nothing" "$out" ""
eq "... and nothing started" "$(started)" not-started
state "$OLD" ""
update; echo "$out"; eq "an older local build: apt-get update succeeds" "$rc" 0
has "... the announcement names the repository's FFmpeg" "$out" "the edition has FFmpeg $V"
eq "... and the stand-in was called with --auto" "$(started)" "--auto"
eq "... no update-check problem" "$(problem)" no-problem
printf '#!/bin/sh\nexit 1\n' >/tmp/pathdir/on_ac_power
update; eq "on battery: apt-get update succeeds" "$rc" 0; has "... the message about the mains power" "$out" "mains power"
eq "... and nothing started" "$(started)" not-started
printf '#!/bin/sh\nexit 0\n' >/tmp/pathdir/on_ac_power
state "$V" ""
update; eq "a local build of the repository's version: apt-get update succeeds" "$rc" 0; eq "... silence" "$out" ""
eq "... and nothing started" "$(started)" not-started
state "$OLD" "$V"
update; echo "$out"; eq "a failed rebuild of that version: apt-get update succeeds" "$rc" 0
has "... the message about it" "$out" "failed earlier"
eq "... and no retry by itself" "$(started)" not-started
state "$OLD" ""
exec 8>/tmp/lock; flock -n 8
update; eq "a rebuild already running: apt-get update succeeds" "$rc" 0; eq "... silence" "$out" ""
eq "... and nothing started" "$(started)" not-started
flock -u 8

# failures the engine keeps and says: apt update itself worked, and its output says them
fixture "$OTHER"
state "$OLD" ""
update; echo "$out"; eq "no source record, kept: apt-get update succeeds" "$rc" 0
has "... its message is in apt-get update's output" "$out" "has no source package ffmpeg-dmo"
hasnt "... and apt reports no failed script" "$out" "$NOKEPT"
has "... the problem is in the engine" "$(problem)" "has no source package ffmpeg-dmo"
eq "... and nothing started" "$(started)" not-started
APT=apt update; eq "... apt update succeeds too" "$rc" 0; has "... with the message" "$out" "has no source package ffmpeg-dmo"
fixture "$GOOD"
mv /etc/apt/sources.list.d/hooktest.list /tmp/hooktest.list.aside
update; echo "$out"; eq "no source line at all, kept: apt-get update succeeds" "$rc" 0
has "... the message names the source line to check" "$out" "sparky-stereo.sources"
has "... the problem is in the engine" "$(problem)" "has no source package ffmpeg-dmo"
mv /tmp/hooktest.list.aside /etc/apt/sources.list.d/hooktest.list
fixture "$INVALID"
update; echo "$out"; eq "an invalid source record, kept: apt-get update succeeds" "$rc" 0
has "... its message is in the output" "$out" "update check failed"
has "... the problem is in the engine" "$(problem)" "update check failed"
eq "... and nothing started" "$(started)" not-started
fixture "$GOOD"
update SPARKY_FDK_LIBDIR=/tmp/no-library; echo "$out"; eq "the library missing, kept: apt-get update succeeds" "$rc" 0
has "... its message is in the output" "$out" "could not load"
has "... the problem is in the engine" "$(problem)" "could not load"
state "$V" ""
sparky-stereo-problems keep --machine --quiet sparky-stereo-ffmpeg-fdk update-check LOCAL77 fixture
update; eq "a later successful check: apt-get update succeeds" "$rc" 0; eq "... silence" "$(quiet "$out")" ""
eq "... and the kept problem is cleared" "$(problem)" no-problem

# failures nothing could keep: apt update fails, visibly
: >/tmp/not-a-folder
fixture "$OTHER"
state "$OLD" ""
update SPARKY_STEREO_ROOT=/tmp/not-a-folder; echo "$out"; eq "the engine cannot keep it: apt-get update fails" "$rc" 100
has "... apt names the hook" "$out" "$NOKEPT"
has "... and the check's own message is still said" "$out" "has no source package ffmpeg-dmo"
APT=apt update SPARKY_STEREO_ROOT=/tmp/not-a-folder; eq "... apt update fails too" "$rc" 100
fixture "$GOOD"
state "" ""
mkdir -p /tmp/engine/var/lib/sparky-stereo-problems/sparky-stereo-ffmpeg-fdk_update-check.json
update; echo "$out"; eq "a clear that fails: apt-get update fails" "$rc" 100; has "... apt names the hook" "$out" "$NOKEPT"
rmdir /tmp/engine/var/lib/sparky-stereo-problems/sparky-stereo-ffmpeg-fdk_update-check.json
update SPARKY_FDK_LIBDIR=/tmp/no-library SPARKY_STEREO_ROOT=/tmp/not-a-folder; echo "$out"
eq "the library missing and the engine broken: apt-get update fails" "$rc" 100; has "... apt names the hook" "$out" "$NOKEPT"
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
