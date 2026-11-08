#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/08
# Copyright 2026 under the GNU GPL3 License
# ORDER 460: ClamAV's two updaters, with the real clamav-freshclam, the real systemd and the real engine.
# DESTRUCTIVE FIXTURE: root in a throwaway systemd-PID-1 container only (clamav-freshclam, sparky-stereo-problems and
# the package OLD installed or installable; no network is needed: freshclam only has to hold its log lock).
# Usage: clamav-updaters.sh OLD.deb NEW.deb [MORE.deb...]   (0.1.5 Breaks Debian's urfkill, so the edition's urfkill debs go with it)
#   OLD is installed first and the state clamav's older package left is made (daemon, once service and timer enabled);
#   the failing boot is reproduced (the once service cannot lock the log the daemon holds); then NEW is installed over it.
#   With NEW = 0.1.5 every check passes; with NEW = OLD (0.1.4) the checks after the install fail: the red run.
set -u
[ "$(cat /run/systemd/container 2>/dev/null)" = docker ] || { echo "not in the systemd test container" >&2; exit 2; }
OLD=${1:?OLD.deb}; shift; NEW=("${@:?NEW.deb}")
FAILS=0
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
DAEMON=clamav-freshclam.service
ONCE=clamav-freshclam-once.service
TIMER=clamav-freshclam-once.timer
st() { systemctl is-enabled "$1" 2>/dev/null; }
reset() { # the state clamav 1.4.3 and older left: all three enabled
	systemctl stop "$DAEMON" "$ONCE" "$TIMER" 2>/dev/null; systemctl reset-failed 2>/dev/null
	systemctl enable "$DAEMON" "$ONCE" "$TIMER" >/dev/null 2>&1
}
race() { # what a boot does: the daemon takes the log lock, the once service comes after it
	systemctl start --no-block "$DAEMON"; sleep 2; systemctl start "$ONCE" >/dev/null 2>&1
}

echo "=== the failing boot, reproduced (OLD installed)"
dpkg -i "$OLD" >/dev/null 2>&1 || { echo "FAIL install OLD"; exit 1; }
reset
ok "old state: daemon, once service and timer are enabled" '[ "$(st $DAEMON) $(st $ONCE) $(st $TIMER)" = "enabled enabled enabled" ]'
race
ok "red reproduced: the once service fails on the log lock the daemon holds" 'systemctl is-failed --quiet $ONCE && journalctl -u $ONCE --no-pager | grep -q "Failed to lock the log file"'
ok "the daemon itself runs" 'systemctl is-active --quiet $DAEMON'

echo "=== NEW installed over OLD (an upgrade)"
apt-get install -y --reinstall --allow-downgrades "${NEW[@]}" >/tmp/new-install.log 2>&1; cat /tmp/new-install.log | grep -i "updater" | head -3
ok "the once service is switched off" '[ "$(st $ONCE)" != enabled ]'
ok "the once timer is switched off" '[ "$(st $TIMER)" != enabled ]'
ok "the daemon stays enabled" '[ "$(st $DAEMON)" = enabled ]'
ok "the daemon still runs" 'systemctl is-active --quiet $DAEMON'
ok "the once service is no longer failed" '! systemctl is-failed --quiet $ONCE'
ok "it was said, in the package's own words" 'grep -q "two virus database updaters" /tmp/new-install.log'
ok "no failure is kept for the migration" '[ -z "$(sparky-stereo-problems list --json sparky-stereo-service-defaults | grep -c clamav-updaters | grep -v ^0)" ]'

echo "=== a later configure of clamav-freshclam does not switch them on again (Debian's was-enabled reads the symlinks)"
dpkg-reconfigure -fnoninteractive clamav-freshclam >/dev/null 2>&1
ok "after clamav's own postinst: once service and timer still off" '[ "$(st $ONCE)" != enabled ] && [ "$(st $TIMER)" != enabled ]'

echo "=== the person's choice is kept: it runs once, at the version that first carries it"
systemctl enable "$TIMER" >/dev/null 2>&1
apt-get install -y --reinstall "${NEW[@]}" >/dev/null 2>&1
ok "the same version configured again leaves a timer the person switched on" '[ "$(st $TIMER)" = enabled ]'
systemctl disable "$TIMER" >/dev/null 2>&1

echo "=== only the failing combination is touched"
reset; systemctl disable "$DAEMON" >/dev/null 2>&1   # once pair on, daemon off: the person runs the daily updater alone
/usr/lib/sparky-stereo-service-defaults/clamav-updaters >/dev/null 2>&1
ok "daemon off, once pair on: left as it is" '[ "$(st $ONCE) $(st $TIMER)" = "enabled enabled" ]'
systemctl disable "$ONCE" "$TIMER" >/dev/null 2>&1; systemctl enable "$DAEMON" >/dev/null 2>&1
/usr/lib/sparky-stereo-service-defaults/clamav-updaters >/tmp/quiet.log 2>&1
ok "daemon on, once pair off: nothing done, nothing said" '[ "$(st $DAEMON)" = enabled ] && [ ! -s /tmp/quiet.log ]'

echo "=== the engine's Repair runs the same helper"
reset
sparky-stereo-problems keep --machine --repair '["/usr/lib/sparky-stereo-service-defaults/clamav-updaters"]' sparky-stereo-service-defaults clamav-updaters LOCAL23 /x 1 >/dev/null 2>&1
sparky-stereo-problems repair --machine sparky-stereo-service-defaults clamav-updaters >/dev/null 2>&1
ok "Repair switches the pair off" '[ "$(st $ONCE)" != enabled ] && [ "$(st $TIMER)" != enabled ]'
ok "and the kept problem is gone" '! sparky-stereo-problems list sparky-stereo-service-defaults 2>/dev/null | grep -q clamav-updaters'
echo "SUMMARY: $FAILS failing"
[ "$FAILS" = 0 ]
