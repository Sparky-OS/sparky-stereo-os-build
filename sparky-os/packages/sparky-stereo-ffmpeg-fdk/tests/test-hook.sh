#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The apt hook (lib/check-update) alone, in a debian:testing container with a repository that has a source index (/repo, the
# repository made by make-repo.sh) and the package folder of the helper (/g, read only): no build is started, the command
# the hook would start is a stand-in that writes down its arguments. The cases:
#   no local build ............................ silence, nothing started
#   local build older than the repository ..... the announcement, the stand-in called with --auto
#   the same on battery (on_ac_power says 1) .. the waiting message, nothing started
#   the same version as the repository ........ silence
#   a failed rebuild of that version .......... the message about the log, nothing started, no retry by itself
#   a rebuild already running (lock held) ..... silence, nothing started
# Usage: docker run --rm --cpus 1 -v REPO:/repo:ro -v SPARKY-OS/packages/sparky-stereo-ffmpeg-fdk:/g:ro debian:testing /g/tests/test-hook.sh
# Last update 2026/10/08
export DEBIAN_FRONTEND=noninteractive
PASS=0; FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
printf 'deb [trusted=yes] file:/repo ./\ndeb-src [trusted=yes] file:/repo ./\n' >/etc/apt/sources.list.d/t.list
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq install python3-minimal util-linux >/dev/null 2>&1
export SPARKY_FDK_LIBDIR=/g/lib SPARKY_FDK_LANGDIR=/g/lang SPARKY_FDK_STATE=/tmp/state SPARKY_FDK_LOCK=/tmp/lock SPARKY_FDK_BIN=/tmp/fakebin LANG=en_US.UTF-8
mkdir -p /tmp/state /tmp/pathdir
printf '#!/bin/sh\necho "$@" >>/tmp/called\n' >/tmp/fakebin; chmod +x /tmp/fakebin
V=$(apt-cache showsrc ffmpeg-dmo | awk '/^Version:/{print $2}' | sort -V | tail -n1)
echo "the repository's ffmpeg-dmo source: $V"
run() { rm -f /tmp/called; PATH=/tmp/pathdir:$PATH bash /g/lib/check-update 2>&1; sleep 1; }
state() { # base version, failure marker
	rm -f /tmp/state/*; echo "accepted" >/tmp/state/consent
	[ -n "$1" ] && printf "LOCAL_BASE='%s'\nLOCAL_VERSION='%s+fdk1'\nLOCAL_USER='tester'\nLOCAL_PACKAGES='ffmpeg'\n" "$1" "$1" >/tmp/state/installed
	[ -n "$2" ] && echo "$2" >/tmp/state/last-failure
	return 0
}
rm -f /tmp/state/*
out=$(run); eq "no local build: silence" "$out" ""; check=$([ -e /tmp/called ] && echo called || echo not-called); eq "... and nothing started" "$check" not-called
OLD=10:9.0.1-dmo1+stereo3d1
state "$OLD" ""
out=$(run); echo "$out"
echo "$out" | grep -q "FFmpeg $V" && ok "an older local build: the announcement names the repository's FFmpeg" || bad "the announcement is missing: [$out]"
eq "... and the stand-in was called with --auto" "$(cat /tmp/called 2>/dev/null)" "--auto"
printf '#!/bin/sh\nexit 1\n' >/tmp/pathdir/on_ac_power; chmod +x /tmp/pathdir/on_ac_power
out=$(run)
echo "$out" | grep -q "mains power" && ok "on battery: the message about the mains power" || bad "no battery message: [$out]"
eq "... and nothing started" "$([ -e /tmp/called ] && echo called || echo not-called)" not-called
printf '#!/bin/sh\nexit 0\n' >/tmp/pathdir/on_ac_power
state "$V" ""
out=$(run); eq "a local build of the repository's version: silence" "$out" ""
eq "... and nothing started" "$([ -e /tmp/called ] && echo called || echo not-called)" not-called
state "$OLD" "$V"
out=$(run); echo "$out"
echo "$out" | grep -q "failed earlier" && ok "a failed rebuild of that version: the message about it" || bad "no failure message: [$out]"
eq "... and no retry by itself" "$([ -e /tmp/called ] && echo called || echo not-called)" not-called
state "$OLD" ""
exec 8>/tmp/lock; flock -n 8
out=$(run); eq "a rebuild already running: silence" "$out" ""
eq "... and nothing started" "$([ -e /tmp/called ] && echo called || echo not-called)" not-called
flock -u 8
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
