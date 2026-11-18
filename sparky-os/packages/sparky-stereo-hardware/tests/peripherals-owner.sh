#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# One owner per device, on recorded devices (ORDER 108, milestone 6). Inside a container as root (the test installs umockdev and udev).
# Mounts: /pkg (the package folder), /orgb (OpenRGB's 60-openrgb.rules, from the published package), env OWNER_RULES (default /pkg/share/peripherals/62-...).
# Red: with OpenLinkHub installed and only OpenRGB's rules, the recorded iCUE LINK hub is given to the person (uaccess): the measured clash.
# Green: with the owner rule it is not; without OpenLinkHub it still is; an empty file in /etc/udev/rules.d gives it back; a device OpenRGB alone
# drives keeps it, and so does a Corsair keyboard (OpenLinkHub drives it too, the edition carries it for hubs, coolers, lighting nodes and power supplies only).
set -uo pipefail
sh /run/https-only-apt.sh >/dev/null 2>&1 || true
export DEBIAN_FRONTEND=noninteractive
apt-get -y -qq update >/dev/null 2>&1; apt-get -y -qq --no-install-recommends install umockdev udev python3 ca-certificates >/dev/null 2>&1
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
RULES=/usr/lib/udev/rules.d
cp /orgb/60-openrgb.rules $RULES/
OWNER=62-sparky-stereo-peripheral-owner.rules
tags() { # DEVICE_FILE SYSPATH -> the device's tags and the owner property
	# CURRENT_TAGS, not TAGS: udev's TAGS keeps a tag that TAG-= removed, and the uaccess builtin reads the current ones
	umockdev-run -d "$1" -- udevadm test --action=add "$2" 2>&1 | grep -E '^  (CURRENT_TAGS|SPARKY_PERIPHERAL_OWNER)=' | tr -d ' ' | tr '\n' ' '
}
HUB=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:1B1C:0C3F.0001/hidraw/hidraw0
WRA=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:2516:0051.0001/hidraw/hidraw0
KBD=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:1B1C:1B11.0001/hidraw/hidraw0
OLH=/opt/OpenLinkHub
rm -rf $OLH /etc/udev/rules.d/$OWNER $RULES/$OWNER
out=$(tags /pkg/tests/peripherals/hub.umockdev $HUB); [[ $out == *uaccess* ]] && ok "the recorded iCUE LINK hub is given to the person by OpenRGB's rules (OpenLinkHub absent): $out" || bad "no uaccess on the hub: $out"
mkdir -p $OLH
out=$(tags /pkg/tests/peripherals/hub.umockdev $HUB); [[ $out == *uaccess* ]] && ok "red: OpenLinkHub installed and no owner rule, the hub is still given to the person (the clash): $out" || bad "red expected uaccess: $out"
cp /pkg/share/peripherals/$OWNER $RULES/
out=$(tags /pkg/tests/peripherals/hub.umockdev $HUB); [[ $out != *uaccess* && $out == *SPARKY_PERIPHERAL_OWNER=openlinkhub* ]] && ok "green: with the owner rule OpenLinkHub owns the hub, no uaccess: $out" || bad "green expected no uaccess: $out"
out=$(tags /pkg/tests/peripherals/wraith.umockdev $WRA); [[ $out == *uaccess* ]] && ok "a device only OpenRGB drives keeps its access with OpenLinkHub installed: $out" || bad "wraith lost uaccess: $out"
out=$(tags /pkg/tests/peripherals/keyboard.umockdev $KBD); [[ $out == *uaccess* && $out != *SPARKY_PERIPHERAL_OWNER* ]] && ok "a Corsair K95 keyboard keeps OpenRGB's access with OpenLinkHub installed: $out" || bad "keyboard lost uaccess: $out"
rmdir $OLH
out=$(tags /pkg/tests/peripherals/hub.umockdev $HUB); [[ $out == *uaccess* && $out != *SPARKY_PERIPHERAL_OWNER* ]] && ok "OpenLinkHub absent: OpenRGB keeps the hub with the owner rule installed: $out" || bad "absent case: $out"
touch /usr/lib/systemd/system/OpenLinkHub.service
out=$(tags /pkg/tests/peripherals/hub.umockdev $HUB); [[ $out != *uaccess* ]] && ok "OpenLinkHub's unit file is enough to own the hub: $out" || bad "unit file case: $out"
: >/etc/udev/rules.d/$OWNER
out=$(tags /pkg/tests/peripherals/hub.umockdev $HUB); [[ $out == *uaccess* ]] && ok "an empty file of the same name in /etc/udev/rules.d gives the hub back to OpenRGB: $out" || bad "override case: $out"
rm -f /etc/udev/rules.d/$OWNER /usr/lib/systemd/system/OpenLinkHub.service

# the telling, once: sparky-stereo-peripheral-owner with a stand-in for the engine
mkdir -p /fx /stub /state; printf 'Bus 001 Device 002: ID 1b1c:0c3f Corsair iCUE LINK System Hub\nBus 001 Device 003: ID 1d6b:0002 Linux Foundation root hub\n' >/fx/lsusb
printf '#!/bin/sh\necho "$@" >>/stub/engine.log\n' >/stub/sparky-stereo-problems; chmod +x /stub/sparky-stereo-problems
run() { PATH=/stub:$PATH SPARKY_PERIPHERAL_FIXTURE=/fx SPARKY_STEREO_ROOT=/state SPARKY_PERIPHERAL_TABLE=/pkg/share/peripherals/owners.tsv python3 /pkg/bin/sparky-stereo-peripheral-owner "$@"; }
echo no >/fx/openlinkhub-upstream; echo no >/fx/openlinkhub-package; echo yes >/fx/openlinkhub; rm -f /stub/engine.log
run check; n1=$(wc -l </stub/engine.log); run check; n2=$(wc -l </stub/engine.log)
[[ $n1 == 1 && $n2 == 1 ]] && ok "told once: one engine call at the first check, none at the second ($(cat /stub/engine.log))" || bad "told $n1 then $n2 times"
grep -q 'say sparky-stereo-hardware LOCAL87' /stub/engine.log && ok "the message is LOCAL87 of the package's catalogue" || bad "wrong call: $(cat /stub/engine.log)"
echo no >/fx/openlinkhub; run check; [[ ! -e /state/var/lib/sparky-stereo-hardware/owner-told/1b1c-0c3f ]] && ok "the telling is forgotten when OpenLinkHub is gone" || bad "mark kept"
echo yes >/fx/openlinkhub; : >/stub/engine.log; run check; [[ $(wc -l </stub/engine.log) == 1 ]] && ok "told again when it comes back" || bad "not told again"
run list | grep -q '^1b1c:0c3f.openlinkhub' && ok "list: $(run list)" || bad "list: $(run list)"
printf 'Bus 001 Device 003: ID 1d6b:0002 Linux Foundation root hub\n' >/fx/lsusb; : >/stub/engine.log; run check; [[ ! -s /stub/engine.log && ! -e /state/var/lib/sparky-stereo-hardware/owner-told/1b1c-0c3f ]] && ok "a device that is gone is not told and its mark is forgotten" || bad "gone device"

# upstream's own OpenLinkHub with the package beside it: one notice, LOCAL89, in the engine's catalogue; not for either alone
echo no >/fx/openlinkhub-upstream; echo no >/fx/openlinkhub-package; : >/stub/engine.log; rm -rf /state/var/lib/sparky-stereo-hardware/owner-told
run check; [[ ! -s /stub/engine.log ]] && ok "neither upstream's copy nor the package: no notice" || bad "notice with neither: $(cat /stub/engine.log)"
echo yes >/fx/openlinkhub-upstream; run check; [[ ! -s /stub/engine.log ]] && ok "upstream's copy alone: no notice" || bad "notice for upstream alone: $(cat /stub/engine.log)"
echo no >/fx/openlinkhub-upstream; echo yes >/fx/openlinkhub-package; run check; [[ ! -s /stub/engine.log ]] && ok "the package alone: no notice" || bad "notice for the package alone: $(cat /stub/engine.log)"
echo yes >/fx/openlinkhub-upstream; run check; run check
[[ $(grep -c 'say sparky-stereo-hardware LOCAL89' /stub/engine.log) == 1 ]] && ok "both: told once in two checks ($(cat /stub/engine.log))" || bad "both: engine log: $(cat /stub/engine.log)"
echo no >/fx/openlinkhub-upstream; run check; [[ ! -e /state/var/lib/sparky-stereo-hardware/owner-told/notice-openlinkhub-upstream ]] && ok "the telling is forgotten when upstream's copy is gone" || bad "notice mark kept"
echo yes >/fx/openlinkhub-upstream; : >/stub/engine.log; run check; [[ $(wc -l </stub/engine.log) == 1 ]] && ok "told again when it comes back" || bad "not told again"
echo no >/fx/openlinkhub-upstream; echo no >/fx/openlinkhub-package; run check
n=$(python3 /pkg/tests/upstream-notice-lang.py 2>&1 | grep -c "^PASS"); [[ $n == 10 ]] && ok "the notice is in the catalogue in all ten languages" || bad "ten languages: $n"

# LACT and HeadsetControl made by upstream's makefile (/usr/local) with the package beside them: one notice each (milestone 11)
for t in lact headsetcontrol; do
	msg=LOCAL91; [[ $t == headsetcontrol ]] && msg=LOCAL93
	echo no >/fx/openlinkhub-upstream; echo no >/fx/openlinkhub-package; echo no >/fx/$t-local; echo no >/fx/$t-package; : >/stub/engine.log
	run check; [[ ! -s /stub/engine.log ]] && ok "$t: neither the /usr/local copy nor the package: no notice" || bad "$t: notice with neither: $(cat /stub/engine.log)"
	echo yes >/fx/$t-local; run check; [[ ! -s /stub/engine.log ]] && ok "$t: the /usr/local copy alone: no notice" || bad "$t: notice for the copy alone"
	echo no >/fx/$t-local; echo yes >/fx/$t-package; run check; [[ ! -s /stub/engine.log ]] && ok "$t: the package alone: no notice" || bad "$t: notice for the package alone"
	echo yes >/fx/$t-local; run check; run check
	[[ $(grep -c "say sparky-stereo-hardware $msg" /stub/engine.log) == 1 ]] && ok "$t: both: told once in two checks ($(cat /stub/engine.log))" || bad "$t: both: engine log: $(cat /stub/engine.log)"
	echo no >/fx/$t-local; run check; [[ ! -e /state/var/lib/sparky-stereo-hardware/owner-told/notice-$t-local ]] && ok "$t: the telling is forgotten when the copy is gone" || bad "$t: mark kept"
	echo yes >/fx/$t-local; : >/stub/engine.log; run check; [[ $(wc -l </stub/engine.log) == 1 ]] && ok "$t: told again when it comes back" || bad "$t: not told again"
	echo no >/fx/$t-local; echo no >/fx/$t-package; run check
done
n=$(python3 /pkg/tests/local-notice-lang.py 2>&1 | grep -c "^PASS"); [[ $n == 10 ]] && ok "the two notices are in the catalogue in all ten languages" || bad "ten languages (LACT, HeadsetControl): $n"

# OpenRGB with the session: only with the mark, never over a person's own entry
mkdir -p /home/t/.config/autostart /state/var/lib/sparky-stereo-hardware; printf '#!/bin/sh\necho "started $@" >>/stub/openrgb.log\n' >/stub/openrgb; chmod +x /stub/openrgb
sess() { HOME=/home/t XDG_CONFIG_HOME=/home/t/.config SPARKY_STEREO_ROOT=/state SPARKY_OPENRGB=/stub/openrgb sh /pkg/bin/sparky-stereo-openrgb-session; }
rm -f /stub/openrgb.log /state/var/lib/sparky-stereo-hardware/openrgb-session
sess; [[ ! -e /stub/openrgb.log ]] && ok "no device it drives (no mark): OpenRGB is not started" || bad "started without a mark"
: >/state/var/lib/sparky-stereo-hardware/openrgb-session
sess; [[ $(cat /stub/openrgb.log 2>/dev/null) == "started --startminimized" ]] && ok "with the mark: started minimized" || bad "mark case: $(cat /stub/openrgb.log 2>/dev/null)"
rm -f /stub/openrgb.log; printf '[Desktop Entry]\nExec=/usr/bin/openrgb --startminimized\n' >/home/t/.config/autostart/OpenRGB.desktop
sess; [[ ! -e /stub/openrgb.log ]] && ok "a person's own OpenRGB autostart entry: ours leaves it to theirs" || bad "double start"
printf '[Desktop Entry]\nExec=/usr/bin/openrgb\nHidden=true\n' >/home/t/.config/autostart/OpenRGB.desktop
sess; [[ -e /stub/openrgb.log ]] && ok "their entry switched off (Hidden=true): ours starts it" || bad "hidden entry case"
exit $failed
