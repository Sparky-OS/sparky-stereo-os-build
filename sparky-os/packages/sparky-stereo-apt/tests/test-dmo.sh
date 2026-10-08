#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# sparky-stereo-apt with deb-multimedia in it, in a plain debian:testing container (NOT the proof base: deb-multimedia must
# come from the package). /repo is the repository (flat, made by make-repo.sh: Origin "Sparky Stereo OS", with deb-multimedia's
# keyring package carried in carried/), /pkgs has the new sparky-stereo-apt, a sparky-stereo-keyring of the same version and a
# stand-in for sparky-apt (SparkyLinux's repository is not in the container). What it proves, each with a check that can fail:
#   - the package installs: its dependency deb-multimedia-keyring comes from the repository's carried/
#   - the deb-multimedia source file is there and apt update reads deb-multimedia's repository with that keyring, without a warning
#   - the pins are read: our FFmpeg and mpv are the candidates, deb-multimedia's builds of them are at -1, and the carried
#     keyring is at 400, below deb-multimedia's own
# Usage: docker run --rm --cpus 2 -v REPO:/repo:ro -v PKGS:/pkgs:ro -v THIS:/t:ro debian:testing /t/test-dmo.sh
# Last update 2026/10/08
export DEBIAN_FRONTEND=noninteractive
PASS=0; FAIL=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
apt-get update -qq >/dev/null 2>&1
apt-get -y -qq install ca-certificates gnupg >/dev/null 2>&1
echo 'deb [trusted=yes] file:/repo ./' >/etc/apt/sources.list.d/test.list
apt-get update -qq 2>&1 | tail -n 2
check "deb-multimedia is not configured before the package" test ! -e /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources
eq "deb-multimedia-keyring is not installed yet" "$(dpkg -l deb-multimedia-keyring 2>/dev/null | grep -c '^ii')" 0
eq "apt cannot find deb-multimedia's FFmpeg yet: ffmpeg's candidate is ours (the repository's only)" "$(apt-cache policy ffmpeg | awk '/Candidate/{print $2}' | grep -c stereo3d)" 1
apt-get -y install /pkgs/sparky-apt-standin_*.deb /pkgs/sparky-stereo-keyring_*.deb /pkgs/sparky-stereo-apt_*.deb >/tmp/i1.log 2>&1; rc=$?
tail -n 4 /tmp/i1.log | cut -c1-160
eq "sparky-stereo-apt installs (its dependencies come from the repository and /pkgs)" "$rc" 0
eq "deb-multimedia-keyring was installed as its dependency" "$(dpkg -l deb-multimedia-keyring | grep -c '^ii')" 1
eq "... from the repository's carried folder (the same bytes as deb-multimedia's package)" "$(dpkg-deb -f /repo/carried/deb-multimedia-keyring_2024.9.1_all.deb Version)" "$(dpkg-query -W -f='${Version}' deb-multimedia-keyring)"
check "the keyring file the source names exists" test -s /usr/share/keyrings/deb-multimedia-keyring.pgp
cat /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources | grep -v '^#'
check "the source says forky, main and non-free, Signed-By the keyring package's file" bash -c "grep -q 'Suites: forky' /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources && grep -q 'Components: main non-free' /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources && grep -q 'Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp' /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources"
rm -f /etc/apt/sources.list.d/sparky-stereo.sources      # its URL is the real repository; the test has its own
out=$(apt-get update 2>&1)
echo "$out" | grep -E "deb-multimedia|^(W|E):" | head -n 8 | cut -c1-160
eq "apt update reads deb-multimedia without a warning or an error" "$(echo "$out" | grep -c -E '^(W|E):')" 0
check "apt update fetched deb-multimedia's index" grep -q 'deb-multimedia.org forky' <<<"$out"
pol=$(apt-cache policy ffmpeg)
echo "$pol" | head -n 12
eq "ffmpeg's candidate is ours" "$(echo "$pol" | awk '/Candidate/{print $2}')" "10:9.0.2-dmo1+stereo3d2"
check "deb-multimedia's ffmpeg is in the list, at -1" bash -c "echo '$pol' | grep -q -E '^ +10:9\.0\.2-dmo1 -1'"
eq "mpv's candidate is ours" "$(apt-cache policy mpv | awk '/Candidate/{print $2}')" "1:0.41.0-dmo9+stereo3d1"
kp=$(apt-cache policy deb-multimedia-keyring)
echo "$kp" | head -n 8
check "the keyring version we carry is at 400 (not the repository's 1001): a newer one from deb-multimedia wins" bash -c "echo '$kp' | grep -q -E '^ (\*\*\* )?2024\.9\.1 400\$'"
check "deb-multimedia's repository offers the keyring at its own 500 or more" bash -c "echo '$kp' | grep -q -E '^ +(500|990) https://www.deb-multimedia.org'"
check "Debian's build of a package we ship is blocked: ffmpeg from Debian at -1" bash -c "echo '$pol' | grep -q -E '^ +7:[0-9.]+-[0-9a-z+]+ -1'"
eq "a dry run installs our ffmpeg and mpv together" "$(apt-get -s --no-install-recommends install ffmpeg mpv 2>&1 | grep -c -E '^Inst (ffmpeg|mpv) .*(stereo3d2|stereo3d1)')" 2
echo "SUMMARY pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
