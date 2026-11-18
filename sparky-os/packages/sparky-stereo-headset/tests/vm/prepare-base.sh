#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# prepare-base.sh VMDIR KG PLASMA_DEBS HEADSETCONTROL_DEB SKILLS_SCRIPTS PKG: the base of the battery proof. VMDIR holds root.img (made by KG/mkroot.sh) and id_ed25519; KG is
# skills/stereo-proof-rig/scripts/kernel-guest; PLASMA_DEBS the folder with plasma-workspace 6.7.4-2+stereo3d10+lc1 (the staged build the proof is about); SKILLS_SCRIPTS
# skills/stereo-proof-rig/scripts (the capture and fake input scripts); PKG this package's folder. It boots an overlay of root.img, installs the staged desktop packages and
# HeadsetControl, puts in the Plasma login scripts, the stand-in of the HeadsetControl program and its state folder, builds the fake input client, and powers the guest off.
# The result is VMDIR/base2.qcow2: never booted again; every run is an overlay of it.
set -euo pipefail
V=$1; KG=$2; PD=$3; HC=$4; SK=$5; PKG=$6; export VMDIR=$V; PORT=2230
cd "$V"; rm -f base2.qcow2; qemu-img create -q -f qcow2 -b root.img -F raw base2.qcow2
bash "$KG/boot.sh" base2.qcow2 $PORT >/dev/null 2>&1 &
for _ in $(seq 90); do bash "$KG/vmroot.sh" $PORT true 2>/dev/null && break; sleep 2; done
R() { bash "$KG/vmroot.sh" $PORT "$1"; }
VER=6.7.4-2+stereo3d10+lc1
L="libbatterycontrol6 libkfontinst6 libkfontinstui6 libklipper6 libklookandfeel6 libkmpris6 libkworkspace6-6 libnotificationmanager1 libtaskmanager6 plasma-workspace plasma-workspace-data qml6-module-org-kde-breeze-components qml6-module-org-kde-notificationmanager qml6-module-org-kde-plasma-clock qml6-module-org-kde-plasma-workspace qml6-module-org-kde-taskmanager"
R 'mkdir -p /pw /deb /t2 /skills /out /run/hs-standin; chmod 777 /out'
for n in $L; do bash "$KG/vmput.sh" $PORT "$(ls $PD/${n}_${VER}_*.deb | head -1)" /pw/; done
bash "$KG/vmput.sh" $PORT /etc/ssl/certs/ca-certificates.crt /run/host-ca.crt
bash "$KG/vmput.sh" $PORT /K3D/partners/https-only-apt.sh /run/https-only-apt.sh
bash "$KG/vmput.sh" $PORT "$HC" /deb/
R 'sh /run/https-only-apt.sh >/dev/null 2>&1; apt-get -y -qq update >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends --allow-downgrades install /pw/*.deb /deb/headsetcontrol_*.deb powerdevil kinfocenter umockdev libwayland-dev libwayland-bin 2>&1 | tail -2; dpkg-query -W plasma-workspace headsetcontrol powerdevil upower'
bash "$KG/vmput.sh" $PORT "$PKG/tests/plasma-login/." /t2/
bash "$KG/vmput.sh" $PORT "$SK/." /skills/
bash "$KG/vmput.sh" $PORT "$PKG/tests/standin/headsetcontrol" /usr/local/bin/headsetcontrol
R 'chmod +x /usr/local/bin/headsetcontrol /t2/*.sh; usermod -aG render,video rig
printf "d /run/hs-standin 0777 root root -\nf /run/hs-standin/battery 0666 root root - 80\nf /run/hs-standin/status 0666 root root - BATTERY_AVAILABLE\nf /run/hs-standin/present 0666 root root - 1\n" > /etc/tmpfiles.d/hs-standin.conf; systemd-tmpfiles --create
sh /skills/build-fakeinput.sh /out >/out/build-fakeinput.log 2>&1; chmod 755 /out/fakeinput; ls /out/fakeinput; sync; systemctl poweroff' || true
for _ in $(seq 60); do kill -0 "$(cat "$V/pid-$PORT" 2>/dev/null)" 2>/dev/null || break; sleep 2; done
echo "base: $V/base2.qcow2"
