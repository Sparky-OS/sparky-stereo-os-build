#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/08
# Copyright 2026 under the GNU GPL3 License
# ORDER 463 in the systemd test container (root, throwaway; sparky-stereo-problems and systemd-zram-generator installed, no
# swap is ever started: containers have no zram). Usage: leftover.sh OLD.deb NEW.deb
#   OLD (20261106.1) is installed, the leftover state of an upgraded edition is made (generator automatic, the marker the
#   preinst writes), then NEW is installed over it. With NEW = OLD every check after the install fails: the red run.
set -u
[ "$(cat /run/systemd/container 2>/dev/null)" = docker ] || { echo "not in the systemd test container" >&2; exit 2; }
OLD=${1:?}; NEW=${2:?}
FAILS=0
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
G=systemd-zram-generator
S=/var/lib/sparky-stereo-kernel-settings
leftover() { # the state of an upgraded edition: generator automatic, marker present
	apt-get install -y -q --reinstall $G >/dev/null 2>&1; apt-mark auto $G >/dev/null; mkdir -p $S; : >$S/leftover-zram-generator; rm -f /run/sparky-stereo-kernel-settings/blocked-zram0
}
state() { dpkg-query -W -f='${db:Status-Status}' $G 2>/dev/null || echo gone; }
waitgone() { for i in $(seq 1 40); do [ "$(state)" != installed ] && return 0; sleep 1; done; return 1; }

echo "=== 1. the leftover of an upgraded edition, automatic and not chosen"
dpkg -i "$OLD" >/dev/null 2>&1 || { echo "FAIL install OLD"; exit 1; }
leftover
ok "the generator is installed, automatic, and the guard holds the setup off" '[ "$(state)" = installed ] && ! /usr/libexec/sparky-stereo/zram-migration --allow'
apt-get install -y -q --reinstall --allow-downgrades "$NEW" >/tmp/n.log 2>&1
waitgone
ok "the generator is purged, once, after the apt run" '[ "$(state)" = gone ]'
ok "the marker and the kept notice are over" '[ ! -e $S/leftover-zram-generator ] && ! sparky-stereo-problems list sparky-stereo-kernel-settings | grep -q leftover-generator'
ok "it was said" 'journalctl --no-pager -t sparky-stereo-problems -b 2>/dev/null | grep -q "was removed" || journalctl --no-pager -b | grep -q "generator the old edition left"'

echo "=== 2. a generator the person chose (apt-mark manual) is kept"
leftover; apt-mark manual $G >/dev/null
/usr/libexec/sparky-stereo/zram-migration --purge-leftover
ok "installed, marker over, guard lets it pass" '[ "$(state)" = installed ] && [ ! -e $S/leftover-zram-generator ] && /usr/libexec/sparky-stereo/zram-migration --allow'

echo "=== 3. ZRAM=on in the old file is a choice"
leftover; printf 'ZRAM=on\n' >/etc/default/sparky-stereo-zram
/usr/libexec/sparky-stereo/zram-migration --purge-leftover
ok "kept" '[ "$(state)" = installed ]'
rm -f /etc/default/sparky-stereo-zram

echo "=== 4. another installed package needs it: it stays, switched off, and the notice names it"
leftover
mkdir -p /tmp/dep/DEBIAN; printf 'Package: needs-zram\nVersion: 1\nArchitecture: all\nMaintainer: t <t@example.org>\nDepends: %s\nDescription: test\n' $G >/tmp/dep/DEBIAN/control; dpkg-deb -b /tmp/dep /tmp/needs-zram.deb >/dev/null; dpkg -i /tmp/needs-zram.deb >/dev/null 2>&1
/usr/libexec/sparky-stereo/zram-migration --purge-leftover
ok "installed and still held off" '[ "$(state)" = installed ] && ! /usr/libexec/sparky-stereo/zram-migration --allow'
ok "the notice names needs-zram" 'sparky-stereo-problems text sparky-stereo-kernel-settings leftover-generator 2>/dev/null | grep -q needs-zram'
dpkg -r needs-zram >/dev/null 2>&1

echo "=== 5. no generator at all"
apt-get purge -y -q $G >/dev/null 2>&1; : >$S/leftover-zram-generator
/usr/libexec/sparky-stereo/zram-migration --purge-leftover
ok "nothing to do, marker over, exit 0" '[ ! -e $S/leftover-zram-generator ]'

echo "=== 6. a failed zram unit is told without the engine's generic Repair"
apt-get install -y -q $G >/dev/null 2>&1; apt-mark manual $G >/dev/null; rm -f $S/leftover-zram-generator
systemctl daemon-reload; sparky-stereo-problems clear --boot sparky-stereo-problems systemd-zram-setup@zram0.service 2>/dev/null
# no zram device in a container: the setup fails for real (the person's own, chosen generator)
systemctl reset-failed 2>/dev/null; systemctl start systemd-zram-setup@zram0.service >/dev/null 2>&1; sleep 3
ok "the unit failed" 'systemctl is-failed --quiet systemd-zram-setup@zram0.service'
ok "a problem is kept for this boot" 'sparky-stereo-problems list --json sparky-stereo-kernel-settings | grep -q zram-setup'
ok "and it has no repair" 'sparky-stereo-problems list --json | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin) if \"zram\" in x[\"key\"]]; sys.exit(0 if r and all(not x.get(\"repair\") for x in r) else 1)"'
ok "the engine's generic handler did not keep the restart repair" '! sparky-stereo-problems list --json | grep -q "systemctl.*restart.*zram"'
echo "SUMMARY: $FAILS failing"
[ "$FAILS" = 0 ]
