#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# Tests lib/offline-packages: the source appears with the image's local repository, not without it,
# and "off" takes the source, its index and the packages away.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
run() { OFFLINE=$T/offline APT_DIR=$T/apt LISTS=$T/lists "$HERE/lib/offline-packages" "$1"; }
mkdir -p $T/lists
run on
check "no local repository: no source" "$(ls $T/apt/sources.list.d 2>/dev/null)" ""
mkdir -p $T/offline; echo "Package: grub-efi-amd64" > $T/offline/Packages; touch $T/offline/grub-efi-amd64_2.14-4_amd64.deb
run on
check "local repository: its source" "$(grep -E '^(URIs|Suites|Trusted):' $T/apt/sources.list.d/sparky-stereo-offline.sources | tr '\n' ' ')" "URIs: file:$T/offline Suites: ./ Trusted: yes "
touch "$T/lists/_usr_share_sparky-stereo_offline-debs_._Packages" "$T/lists/deb.debian.org_debian_dists_testing_InRelease"
run off
check "off: the source goes" "$(ls $T/apt/sources.list.d)" ""
check "off: its index goes, others stay" "$(ls $T/lists)" "deb.debian.org_debian_dists_testing_InRelease"
check "off: the packages go" "$(ls -d $T/offline 2>/dev/null)" ""
run nonsense 2>/dev/null; check "an unknown word: status 2" "$?" 2
echo "offline-packages: $pass passed, $fail failed"
[ "$fail" = 0 ]
