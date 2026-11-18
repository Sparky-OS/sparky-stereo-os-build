#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Proof inside a container as root (docker run ... -v DEBS:/deb:ro -v THIS_FOLDER:/t:ro IMAGE bash /t/udev-proof.sh): the package installed by apt with the headsetcontrol it depends on,
# the rules starting the person's headset service for a recorded headset (umockdev, the HyperX Cloud II Wireless dongle 03f0:018b: no headset needed) and for no other device,
# the list of the rules equal to the list of the program (headsetcontrol -u), an upgrade, a removal and a purge that leave the person's choices alone.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
sh /run/https-only-apt.sh >/dev/null 2>&1 || true
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install umockdev udev ca-certificates >/dev/null 2>&1
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
HS=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:03F0:018B.0001/hidraw/hidraw0
OT=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:03F0:FFFF.0001/hidraw/hidraw0
props() { umockdev-run -d "$1" -- udevadm test --action=add "$2" 2>&1 | grep -E '^ *(SYSTEMD_USER_WANTS|TAGS|CURRENT_TAGS)=' | tr '\n' ' '; }
echo "== before: no package"
out=$(props /t/udev/headset.umockdev $HS); [[ $out != *SYSTEMD_USER_WANTS* ]] && ok "the recorded HyperX headset starts nothing without the package: $out" || bad "service wanted before: $out"
echo "== installed by apt (headsetcontrol comes with it)"
apt-get -y --no-install-recommends install /deb/headsetcontrol_*_amd64.deb /deb/sparky-stereo-headset_*_amd64.deb >/tmp/i1.log 2>&1; [[ $? == 0 ]] && ok "apt installs the package with headsetcontrol" || bad "install: $(tail -3 /tmp/i1.log)"
dpkg-deb -I /deb/sparky-stereo-headset_*_amd64.deb | grep Depends | cut -c1-260
RULE=/usr/lib/udev/rules.d/71-sparky-stereo-headset.rules
[[ -f $RULE ]] && ok "the rules are installed" || bad "no rules file"
out=$(props /t/udev/headset.umockdev $HS); [[ $out == *"SYSTEMD_USER_WANTS=sparky-stereo-headset.service"* && $out == *systemd* ]] && ok "the recorded headset (03f0:018b) wants the person's headset service: $out" || bad "no service wanted: $out"
out=$(props /t/udev/other.umockdev $OT); [[ $out != *SYSTEMD_USER_WANTS* ]] && ok "a device of the same maker that the program does not list (03f0:ffff) wants nothing: $out" || bad "unlisted device wants the service: $out"
ids() { grep -o 'idVendor}=="[0-9a-f]*", ATTRS{idProduct}=="[0-9a-f]*"' | sort -u; }
/usr/bin/headsetcontrol -u 2>/dev/null | ids >/tmp/prog.ids; ids <$RULE >/tmp/ours.ids
[[ -s /tmp/prog.ids && $(cat /tmp/prog.ids) == "$(cat /tmp/ours.ids)" ]] && ok "the headsets of the rules are the headsets of the program: $(wc -l </tmp/ours.ids) ids" || bad "lists differ: $(diff /tmp/prog.ids /tmp/ours.ids | head -4)"
[[ -x /usr/bin/sparky-stereo-headset && -f /usr/lib/systemd/user/sparky-stereo-headset.service && -L /usr/lib/systemd/user/default.target.wants/sparky-stereo-headset.service ]] && ok "the command and the user service (wanted by default.target) are there" || bad "command or unit missing"
out=$(sparky-stereo-headset 2>&1); [[ $out == *Usage* ]] && ok "the command answers" || bad "command silent"
out=$(HOME=/tmp/nohome QT_QPA_PLATFORM=offscreen /usr/bin/sparky-stereo-headset status 2>&1 | tail -1); [[ $out == "No headset that HeadsetControl knows is connected." ]] && ok "with no headset it says so: $out" || bad "no-headset case: $out"
echo "== a choice of the person, then upgrade, removal and purge"
mkdir -p /root/.config; printf '[Headset 03f0:018b]\nInactiveTime=30\n' >/root/.config/sparky-stereo-headsetrc
rm -rf /tmp/b && mkdir /tmp/b && dpkg-deb -R /deb/sparky-stereo-headset_*_amd64.deb /tmp/b/pkg && sed -i 's/^Version: .*/Version: 0.1.1+lc1/' /tmp/b/pkg/DEBIAN/control && dpkg-deb -b /tmp/b/pkg /tmp/b/o.deb >/dev/null 2>&1
apt-get -s --no-install-recommends install /tmp/b/o.deb 2>&1 | grep -E "^(Inst|Remv)" | cut -c1-110
apt-get -y --no-install-recommends install /tmp/b/o.deb >/tmp/i2.log 2>&1; [[ $? == 0 && $(dpkg -s sparky-stereo-headset | sed -n 's/^Version: //p') == 0.1.1+lc1 ]] && ok "the upgrade installs without a removal" || bad "upgrade: $(tail -2 /tmp/i2.log)"
out=$(props /t/udev/headset.umockdev $HS); [[ $out == *SYSTEMD_USER_WANTS* ]] && ok "after the upgrade the recorded headset still wants the service" || bad "service lost: $out"
apt-get -y remove sparky-stereo-headset >/tmp/i3.log 2>&1; [[ ! -e $RULE && ! -e /usr/bin/sparky-stereo-headset ]] && ok "removal takes the files away" || bad "files left after removal"
[[ -f /root/.config/sparky-stereo-headsetrc ]] && ok "the person's choices stay after removal" || bad "choices lost on removal"
out=$(props /t/udev/headset.umockdev $HS); [[ $out != *SYSTEMD_USER_WANTS* ]] && ok "after removal the headset starts nothing" || bad "service still wanted"
apt-get -y purge sparky-stereo-headset >/tmp/i4.log 2>&1; [[ -f /root/.config/sparky-stereo-headsetrc ]] && ok "purge leaves the person's home alone" || bad "purge touched the home"
exit $failed
