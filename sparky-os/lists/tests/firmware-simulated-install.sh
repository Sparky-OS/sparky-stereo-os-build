#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Proves that the hardware list reaches the install: builds the control file of
# sparky-stereo-hardware-support from a lists directory with make-meta.py, puts that package in
# a scratch repository beside the edition's repository, and in a debian:testing container
# simulates (apt-get -s) installing it. Every firmware package the plan adds must appear as
# "Inst". Usage: firmware-simulated-install.sh [lists-dir] (default: the lists beside this
# test). The lists of an older commit can be given to see the test fail on them.
# Needs docker as the user, the edition's repository at ${SPARKY_REPO_DIR}, no network
# beyond the Debian mirror. Last update 2026/10/05
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LISTS=$(cd "${1:-$HERE/..}" && pwd)
WORK=${WORK:-${SPARKY_WORKSPACES:?}/gaming-rig-steps/work}
REPO=${REPO:-${SPARKY_REPO_DIR:?}}
# Added by plan step 1 (2026-10-05): the Wi-Fi, Bluetooth, Intel and sound-amplifier firmware
# Debian's live task and forky's non-free-firmware hold, which the lists lacked.
WANT="firmware-mediatek bluez-firmware firmware-ipw2x00 firmware-intel-graphics firmware-intel-misc firmware-cirrus"

T=$WORK/meta-test.$$
mkdir -p "$T/out" "$T/scratch"
trap 'rm -rf "$T"' EXIT
# make-meta.py reads the lists beside itself: run a copy next to the lists given
cp "$HERE/../make-meta.py" "$T/make-meta.py"
for f in "$LISTS"/*.list; do cp "$f" "$T/"; done
REPO=$REPO python3 "$T/make-meta.py" 99999999 "$T/out"
D=$T/scratch/sparky-stereo-hardware-support
mkdir -p "$D"
cp -r "$T/out/sparky-stereo-hardware-support/DEBIAN" "$D/"
dpkg-deb --root-owner-group -b "$D" "$T/scratch/" >/dev/null
(cd "$T/scratch" && dpkg-scanpackages . 2>/dev/null >Packages) || \
	docker run --rm -v "$T/scratch:/s" debian:testing bash -c 'apt-get update -qq >/dev/null; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dpkg-dev >/dev/null; cd /s && dpkg-scanpackages . >Packages 2>/dev/null'
rm -rf "$D"

OUTFILE=$T/sim.out
docker run --rm -e DEBIAN_FRONTEND=noninteractive -e LC_ALL=C \
	-v "$REPO:$REPO:ro" -v "$T/scratch:/scratch:ro" debian:testing bash -c '
rm -f /etc/apt/sources.list.d/*
cat >/etc/apt/sources.list.d/d.sources <<S
Types: deb
URIs: http://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
S
echo "deb [trusted=yes] file:'"$REPO"' ./" >/etc/apt/sources.list.d/ours.list
echo "deb [trusted=yes] file:/scratch ./" >/etc/apt/sources.list.d/scratch.list
apt-get update -qq >/dev/null
apt-get -s -y install sparky-stereo-hardware-support' >"$OUTFILE" 2>&1 || { tail -20 "$OUTFILE"; echo "FAIL: the simulated install did not succeed"; exit 2; }
rc=0
for p in $WANT; do
	if grep -q "^Inst $p " "$OUTFILE"; then echo "ok   $p is installed by sparky-stereo-hardware-support"
	else echo "FAIL $p is not installed by sparky-stereo-hardware-support"; rc=1; fi
done
exit $rc
