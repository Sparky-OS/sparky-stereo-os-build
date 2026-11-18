#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# battery-proof.sh VMDIR KG BASE RED_DEB GREEN_DEB OUT: the headset's battery in Plasma's own list, in a guest that runs the edition's kernel (KVM, never the station's /sys or a real
# device): a real kernel (uhid, hid-input), real udev, real UPower (Debian's), real PowerDevil, real Plasma session (plasma-workspace +stereo3d10, KWin virtual output). The
# headset is a stand-in of the HeadsetControl program for the HyperX Cloud II Wireless dongle (03f0:018b: the kernel has no driver for it) and the dongle's hidraw node a uhid device
# with its numbers, which wants the battery service the way the real rule does. RED: the staged 0.1.0 (no battery in the list; our own low-battery notice). GREEN: 0.2.0.
# BASE is the qcow2 of prepare-base.sh; each run is an overlay of it; OUT receives the screenshots and the lines below (PASS/FAIL).
set -uo pipefail
V=$1; KG=$2; BASE=$3; RED=$4; GREEN=$5; OUT=$6; export VMDIR=$V
mkdir -p "$OUT"; failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
boot() { local n=$1 p=$2; rm -f "${V:?}/${n:?}.qcow2"; qemu-img create -q -f qcow2 -b "$BASE" -F qcow2 "$V/$n.qcow2"; bash "$KG/boot.sh" "$V/$n.qcow2" $p >/dev/null 2>&1 & for _ in $(seq 90); do bash "$KG/vmroot.sh" $p true 2>/dev/null && return 0; sleep 2; done; return 1; }
halt() { bash "$KG/vmroot.sh" $1 'sync; systemctl poweroff' 2>/dev/null; for _ in $(seq 60); do kill -0 "$(cat "$V/pid-$1" 2>/dev/null)" 2>/dev/null || return 0; sleep 2; done; }
R() { bash "$KG/vmroot.sh" $P "$1"; }
U() { bash "$KG/vmrig.sh" $P "$1"; }
shot() { U "bash /t2/shot.sh $1 >/dev/null 2>&1"; bash "$KG/vmget.sh" $P /out/$1.png "$OUT/$1.png"; }
session() { R 'cd /; (nohup runuser -u rig -- env STANDIN=/usr/local/bin HS_STANDIN_DIR=/run/hs-standin POWERDEVIL=1 POPUPS=/skills/tray-menu-count/popups.js QT_LOGGING_RULES="js.debug=true" bash /t2/session-up.sh >/out/session.log 2>&1 &); for i in $(seq 120); do test -f /tmp/xdg-rig/up && break; sleep 2; done; test -f /tmp/xdg-rig/up && echo up'; }
notes() { U 'grep -c "member=Notify" $XDG_RUNTIME_DIR/notify.log'; }
notetext() { U 'grep -A14 "member=Notify" $XDG_RUNTIME_DIR/notify.log | grep -E "string \"[^x]" | grep -v "x-kde" | head -6'; }
tray() { U 'bash /t2/click.sh m:1478,870 s:400 b:272 s:1500 >/dev/null 2>&1'; }
# the counters of tray-menu-count/lib.sh for a guest: a menu of the entry is a popup window that is not the tray's own 218x100 one
appmenus() { R 'grep POPUPLOG /tmp/xdg-rig/kwin.log | grep "popup=true" | grep -vc "w=218 h=100"'; }
S1() { local B=$(appmenus); local Q="m:900,500 s:300 m:1449,871 s:300 m:1450,870 b:273 s:1500 k:1 s:800"; U "bash /t2/click.sh $Q $Q $Q $Q $Q $Q $Q $Q $Q $Q >/dev/null 2>&1"; echo $(( $(appmenus) - B )); }
S2() { local B=$(appmenus); local Q="m:900,500 s:300 m:1449,871 s:300 m:1450,870 b:273 s:1500 k:1 s:800 m:1449,871 s:300 m:1450,870 b:272 s:1800 k:1 s:800"; U "bash /t2/click.sh $Q $Q $Q $Q $Q $Q $Q $Q $Q $Q >/dev/null 2>&1"; echo $(( $(appmenus) - B )); }
HS='/run/hs-standin'; UP=/org/freedesktop/UPower/devices/battery_hid_sparky_stereo_headseto03f0o018b_battery_1
setst() { R "echo $1 > $HS/battery; echo $2 > $HS/status"; }

echo "################ RED: the staged sparky-stereo-headset 0.1.0 (desktop set +stereo3d10)"
P=2223; boot red $P || { bad "the red guest did not start"; exit 1; }
R 'uname -r; mkdir -p /deb'; bash "$KG/vmput.sh" $P "$RED" /deb/
R 'DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install /deb/sparky-stereo-headset_*.deb 2>&1 | tail -1; dpkg-query -W sparky-stereo-headset'
session | grep -q up && ok "the Plasma session is up (red)" || bad "no session (red)"
U '(nohup sparky-stereo-headset watch >/out/watch.log 2>&1 &); sleep 3'
out=$(R 'upower -e'); [[ $out != *battery_* ]] && ok "red: UPower lists no battery but the display device: $(echo $out | tr '\n' ' ')" || bad "red: a battery is listed: $out"
tray; shot red-tray; U 'bash /t2/click.sh k:1 s:500 >/dev/null 2>&1'
U '(nohup kinfocenter kcm_energyinfo >/out/kinfo.log 2>&1 &); sleep 12'; shot red-energy; U 'pkill -x kinfocenter'
setst 8 BATTERY_AVAILABLE; sleep 34
n=$(notes); t=$(notetext); [[ $n == 1 && $t == *"Headset battery low"* && $t != *"Power Management"* ]] && ok "red: one notice at 8 %, ours (\"Headset battery low\"), none from PowerDevil" || bad "red notices: $n / $t"
echo "$t" | sed 's/^/   /'; shot red-lowbattery
halt $P

echo "################ GREEN: sparky-stereo-headset 0.2.0"
P=2224; boot green $P || { bad "the green guest did not start"; exit 1; }
R 'mkdir -p /deb'; bash "$KG/vmput.sh" $P "$GREEN" /deb/; bash "$KG/vmput.sh" $P "$KG/dongle.py" /root/
R 'DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install /deb/sparky-stereo-headset_*.deb 2>&1 | tail -1; dpkg-query -W sparky-stereo-headset
echo "installing started the battery service: $(systemctl is-active sparky-stereo-headset-battery) (inactive is right)"
mkdir -p /etc/systemd/system/sparky-stereo-headset-battery.service.d; printf "[Service]\nEnvironment=HS_STANDIN_DIR=/run/hs-standin\nReadWritePaths=/run/hs-standin\n" > /etc/systemd/system/sparky-stereo-headset-battery.service.d/standin.conf
cat > /etc/udev/rules.d/99-gr108-dongle.rules <<"EOR"
# TEST ONLY: the stand-in dongle (a uhid hidraw device, bus 0003, 03f0:018b) wants the service as the real rule does for the real dongle (ATTRS{idVendor} needs a USB parent)
SUBSYSTEM=="hidraw", ACTION=="add", KERNELS=="0003:03F0:018B.*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="sparky-stereo-headset-battery.service"
EOR
systemctl daemon-reload; udevadm control --reload'
session | grep -q up && ok "the Plasma session is up (green)" || bad "no session (green)"
U '(nohup sparky-stereo-headset watch >/out/watch.log 2>&1 &); sleep 2'
R '(nohup python3 /root/dongle.py 7200 > /root/dongle.log 2>&1 &); sleep 9'
[[ $(R 'systemctl is-active sparky-stereo-headset-battery') == active ]] && ok "the dongle appears: udev starts the battery service (SYSTEMD_WANTS)" || bad "service not started by the dongle"
out=$(R "busctl get-property org.freedesktop.UPower $UP org.freedesktop.UPower.Device Type Model Percentage State 2>&1 | tr '\n' ' '")
[[ $out == *"u 17"* && $out == *'"HyperX Cloud II Wireless"'* && $out == *"d 80"* && $out == *"u 2"* ]] && ok "green: UPower lists the headset: $out (Type 17 is a headset, State 2 discharging)" || bad "green UPower: $out"
tray; shot green-tray; U 'bash /t2/click.sh m:1460,464 s:400 b:272 s:3000 >/dev/null 2>&1'; shot green-applet
setst 35 BATTERY_CHARGING; sleep 34
out=$(R "busctl get-property org.freedesktop.UPower $UP org.freedesktop.UPower.Device Percentage State 2>&1 | tr '\n' ' '"); [[ $out == *"d 35"* && $out == *"u 1"* ]] && ok "green: charging at 35 %: $out" || bad "charging: $out"
shot green-applet-charging; U 'bash /t2/click.sh k:1 s:500 >/dev/null 2>&1'
U '(nohup kinfocenter kcm_energyinfo >/out/kinfo.log 2>&1 &); sleep 12'; shot green-energy; U 'pkill -x kinfocenter'
b=$(notes); setst 8 BATTERY_AVAILABLE; sleep 34
n=$(( $(notes) - b )); t=$(notetext)
[[ $n == 1 && $t == *"Device Battery Low (8% Remaining)"* && $t == *"audio-headset-battery"* && $t == *"HyperX Cloud II Wireless"* && $t != *"Headset battery low"* ]] && ok "green: one notice at 8 %, PowerDevil's own at its own level, none of ours" || bad "green notices: $n / $t"
echo "$t" | sed 's/^/   /'; shot green-lowbattery
setst 8 BATTERY_UNAVAILABLE; sleep 34
[[ $(R 'upower -e') != *battery_hid* ]] && ok "green: the headset switched off: the entry is gone (no stale 8 %)" || bad "entry stays after the headset is off"
tray; shot green-off-tray; U 'bash /t2/click.sh k:1 s:500 >/dev/null 2>&1'
setst 62 BATTERY_AVAILABLE; sleep 34
out=$(R "busctl get-property org.freedesktop.UPower $UP org.freedesktop.UPower.Device Percentage 2>&1"); [[ $out == "d 62" ]] && ok "green: the headset on again: back at 62 %" || bad "back on: $out"
x=$(S1); [[ $x == 10 ]] && ok "green: ten right clicks in a row on the tray entry: $x menus of 10, with the battery in the list" || bad "right clicks in a row: $x of 10"
x=$(S2); [[ $x == 10 ]] && ok "green: ten right clicks after a left click: $x menus of 10" || bad "right clicks after a left click: $x of 10"
R 'pkill -x python3; sleep 5'
[[ $(R 'upower -e') != *battery_hid* && $(R 'systemctl is-active sparky-stereo-headset-battery') != active ]] && ok "green: the dongle unplugged: the entry is gone and the service stopped with it" || bad "after unplug: $(R 'upower -e') $(R 'systemctl is-active sparky-stereo-headset-battery')"
R '(nohup python3 /root/dongle.py 7200 > /root/dongle.log 2>&1 &); sleep 10'; [[ $(R 'upower -e') == *battery_hid* ]] && ok "green: plugged again: the entry is back" || bad "no entry after replug"
out=$(R 'systemd-run --wait --pipe -p DevicePolicy=closed -p DeviceAllow="char-hidraw rw" -p DeviceAllow="/dev/uhid rw" -p CapabilityBoundingSet= -p NoNewPrivileges=yes -p ProtectSystem=strict -p PrivateNetwork=yes -p SystemCallFilter=@system-service -p MemoryDenyWriteExecute=yes python3 -c "
import os,glob
for d in glob.glob(\"/dev/hidraw*\"):
    os.close(os.open(d, os.O_RDWR)); print(\"opened\", d)
os.close(os.open(\"/dev/uhid\", os.O_RDWR)); print(\"opened /dev/uhid\")
try: os.open(\"/dev/input/event0\", os.O_RDONLY); print(\"event0 opened\")
except Exception as e: print(\"event0 refused\")
" 2>&1 | grep -E "opened|refused"'); [[ $out == *"opened /dev/hidraw"* && $out == *"opened /dev/uhid"* && $out == *"event0 refused"* ]] && ok "the unit's sandbox lets a process open a hidraw node and /dev/uhid and nothing else: $(echo $out | tr '\n' ' ')" || bad "sandbox: $out"
R 'journalctl -u sparky-stereo-headset-battery --no-pager | tail -12' >"$OUT/green-service.log"
halt $P
echo "failed=$failed"; exit $failed
