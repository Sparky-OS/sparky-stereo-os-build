#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# ORDER 40: a SenseGlove Nova on firmware 1.x pairs over Bluetooth Classic (serial port profile) and appears as /dev/rfcomm0; SenseCom
# (SenseGlove's install page: "sudo adduser $USER dialout") opens it, so the person's account needs the group dialout.
# This proves, with no glove and no Bluetooth adapter (umockdev), that (1) Debian's udev already gives rfcomm nodes the group dialout,
# so no rule of ours is needed, and (2) a new account gets dialout from this package's list. Each has a control that must fail.
# Run as root in a container with the edition's repository and pins: docker run ... IMAGE bash glove-serial.sh
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get -y -qq --no-install-recommends install umockdev udev adduser sparky-stereo-user-groups >/dev/null 2>&1 || { echo "FAIL install"; exit 1; }
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cat >"$T/rfcomm.umockdev" <<'D'
P: /devices/virtual/tty/rfcomm0
N: rfcomm0
E: DEVNAME=/dev/rfcomm0
E: DEVPATH=/devices/virtual/tty/rfcomm0
E: MAJOR=216
E: MINOR=0
E: SUBSYSTEM=tty
D
gid() { umockdev-run -d "$1" -- udevadm test --action=add /devices/virtual/tty/rfcomm0 2>&1 | awk '/^Device node owner group:/{getline; if (match($0,/gid=[0-9]+/)) print substr($0,RSTART+4,RLENGTH-4)}' | head -1; }
DIALOUT=$(getent group dialout | cut -d: -f3)
echo "== 1. the serial node of a paired glove"
g=$(gid "$T/rfcomm.umockdev"); [[ -n $g && $g == "$DIALOUT" ]] && ok "udev gives /dev/rfcomm0 the group dialout ($g) with Debian's own rules" || bad "rfcomm0 gid '$g', dialout is $DIALOUT"
mkdir -p /etc/udev/rules.d && : >/etc/udev/rules.d/50-udev-default.rules
g=$(gid "$T/rfcomm.umockdev"); [[ $g != "$DIALOUT" ]] && ok "control: with Debian's default rules masked the node is not in dialout (gid '${g:-none}')" || bad "control did not fail: $g"
rm -f /etc/udev/rules.d/50-udev-default.rules
echo "== 2. a new account"
grep -qx dialout /etc/sparky-stereo/user-groups && ok "dialout is in /etc/sparky-stereo/user-groups" || bad "dialout is not in the list"
sparky-stereo-user-groups apply >/dev/null 2>&1
adduser --quiet --disabled-password --gecos "" glovefan >/dev/null 2>&1
id -nG glovefan | tr ' ' '\n' | grep -qx dialout && ok "adduser puts a new account in dialout: $(id -nG glovefan)" || bad "glovefan: $(id -nG glovefan)"
sparky-stereo-user-groups remove >/dev/null 2>&1
adduser --quiet --disabled-password --gecos "" glovefoe >/dev/null 2>&1
id -nG glovefoe | tr ' ' '\n' | grep -qx dialout && bad "control did not fail: $(id -nG glovefoe)" || ok "control: with the list removed a new account is not in dialout ($(id -nG glovefoe))"
exit $failed
