#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Proof inside a container as root (docker run ... -v BUILD_OUT:/deb:ro -v THIS_FOLDER:/t:ro IMAGE bash /t/udev-proof.sh): the package installed by apt,
# the rules giving a recorded headset its device file (umockdev: no headset needed), the program saying plainly that no headset is connected,
# an upgrade, removal, purge, and a copy made by upstream's makefile in /usr/local left byte for byte alone.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
sh /run/https-only-apt.sh >/dev/null 2>&1 || true
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install umockdev udev ca-certificates >/dev/null 2>&1
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
RULE=/usr/lib/udev/rules.d/70-headsets.rules
tags() { umockdev-run -d "$1" -- udevadm test --action=add "$2" 2>&1 | grep -E '^  CURRENT_TAGS=' | tr -d ' ' | tr '\n' ' '; }
HS=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:03F0:018B.0001/hidraw/hidraw0
OT=/devices/pci0000:00/usb1/1-1/1-1:1.0/0003:03F0:FFFF.0001/hidraw/hidraw0
DEB=$(ls /deb/headsetcontrol_*+lc1_amd64.deb)
echo "== before: no rules, no uaccess"
out=$(tags /t/udev/headset.umockdev $HS); [[ $out != *uaccess* ]] && ok "the recorded HyperX headset has no uaccess without the package: $out" || bad "uaccess before: $out"
echo "== a copy made by upstream's makefile (/usr/local) before ours"
mkdir -p /usr/local/bin /usr/local/lib/udev/rules.d
printf '#!/bin/sh\necho upstream copy\n' >/usr/local/bin/headsetcontrol; chmod +x /usr/local/bin/headsetcontrol
printf '# upstream copy of the rules\nKERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="03f0", ATTRS{idProduct}=="018b", TAG+="uaccess"\n' >/usr/local/lib/udev/rules.d/70-headsets.rules
fp() { sha256sum /usr/local/bin/headsetcontrol /usr/local/lib/udev/rules.d/70-headsets.rules | sha256sum | cut -c1-16; }
F0=$(fp)
echo "== installed by apt"
apt-get -y --no-install-recommends install "$DEB" >/tmp/i1.log 2>&1; [[ $? == 0 ]] && ok "apt installs the package" || bad "install: $(tail -3 /tmp/i1.log)"
dpkg-deb -I "$DEB" | grep Depends | cut -c1-200
out=$(tags /t/udev/headset.umockdev $HS); [[ $out == *uaccess* ]] && ok "the listed headset (03f0:018b) is given to the person: $out" || bad "no uaccess: $out"
out=$(tags /t/udev/other.umockdev $OT); [[ $out != *uaccess* ]] && ok "a device of the same maker that the program does not list (03f0:ffff) is not: $out" || bad "unlisted device got uaccess: $out"
code() { grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$'; }   # Lean Code leaves out the comments of installed files (the device names)
/usr/bin/headsetcontrol -u 2>/dev/null | code | diff -q - <(code <$RULE) >/dev/null && ok "the installed rules are, comments aside, exactly what the installed program writes (headsetcontrol -u)" || bad "rules differ from headsetcontrol -u"
/usr/bin/headsetcontrol --help >/dev/null 2>&1; [[ $? == 0 ]] && ok "headsetcontrol --help runs" || bad "--help fails"
out=$(/usr/bin/headsetcontrol -b 2>&1); rc=$?; [[ $rc != 0 && -n $out ]] && ok "with no headset it says so and fails (exit $rc): $(echo "$out" | head -1 | cut -c1-80)" || bad "no-headset case: rc=$rc out=$out"
[[ $(fp) == $F0 ]] && ok "upstream's copy in /usr/local is untouched by the install" || bad "upstream copy changed"
echo "== upgrade"
rm -rf /tmp/b && mkdir /tmp/b && dpkg-deb -R "$DEB" /tmp/b/pkg && sed -i 's/^Version: .*/Version: 4.3.0-92+lc1/' /tmp/b/pkg/DEBIAN/control && dpkg-deb -b /tmp/b/pkg /tmp/b/o.deb >/dev/null 2>&1
apt-get -s --no-install-recommends install /tmp/b/o.deb 2>&1 | grep -E "^(Inst|Remv)" | cut -c1-110
apt-get -y --no-install-recommends install /tmp/b/o.deb >/tmp/i2.log 2>&1; [[ $? == 0 && $(dpkg -s headsetcontrol | sed -n 's/^Version: //p') == 4.3.0-92+lc1 ]] && ok "the upgrade installs without a removal" || bad "upgrade: $(tail -2 /tmp/i2.log)"
out=$(tags /t/udev/headset.umockdev $HS); [[ $out == *uaccess* ]] && ok "after the upgrade the headset is still given to the person" || bad "uaccess lost: $out"
echo "== removal and purge"
apt-get -y remove headsetcontrol >/dev/null 2>&1; [[ ! -e $RULE && ! -e /usr/bin/headsetcontrol ]] && ok "removal takes the program and the rules" || bad "files left"
[[ $(fp) == $F0 ]] && ok "upstream's copy untouched by the removal" || bad "upstream copy changed by removal"
apt-get -y purge headsetcontrol >/dev/null 2>&1; [[ -z $(dpkg -L headsetcontrol 2>/dev/null | xargs -I{} sh -c 'test -f {} && echo {}') ]] && ok "purge leaves no file of the package" || bad "files after purge"
[[ $(fp) == $F0 ]] && ok "upstream's copy untouched by the purge" || bad "upstream copy changed by purge"
rm -f /usr/local/lib/udev/rules.d/70-headsets.rules
out=$(tags /t/udev/headset.umockdev $HS); [[ $out != *uaccess* ]] && ok "with the package gone and no copy, the headset is not given away: $out" || bad "uaccess after purge: $out"
exit $failed
