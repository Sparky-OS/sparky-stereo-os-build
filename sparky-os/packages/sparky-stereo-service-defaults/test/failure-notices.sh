#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# DESTRUCTIVE FIXTURE: root in a throwaway systemd-PID-1 container only.
# Install service-defaults, problems, problems-plasma, python3-dbus, python3-gi,
# dbus-user-session first. No host session or display. Argument 1 is the engine's
# fake-notifications.py; argument 2 is a writable evidence directory.
# Real installed handlers/engine/notifier, synthetic failing service executables.
# Always expects ONE record and ONE Notify call; the old package must exit 1.
set -euo pipefail
[ "$(cat /run/systemd/container)" = docker ]
E=${2:?evidence directory}; mkdir -p "$E"
B=sparky-stereo-problems
units=(urfkill.service snmptt.service ipwatchd.service pkcs11-daemon.service xfs_healer@-.service xfs_healer@test.service order368-other.service order368-other@x.service stafd.service)
# New session each run; records outside this suite are hidden, not deleted.
PERSON="proof${RANDOM}"
useradd -m "$PERSON"
U=$(id -u "$PERSON"); H=$(getent passwd "$PERSON" | cut -d: -f6)
ux() { runuser -u "$PERSON" -- env HOME="$H" XDG_RUNTIME_DIR="/run/user/$U" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$U/bus" "$@"; }
waitfor() { for ((i=0;i<60;i++)); do if "$@"; then return 0; fi; sleep 0.25; done; return 1; }
cleanup() { ux systemctl --user stop sparky-stereo-problems-notifier.service sparky-stereo-problems-notifier.path fake-notifications.service || true; loginctl terminate-user "$PERSON" || true; loginctl disable-linger "$PERSON" || true; }
trap cleanup EXIT
systemctl stop "${units[@]}" 2>/dev/null || true
# Base units replace only the daemons: retain every installed package drop-in.
for unit in urfkill.service snmptt.service ipwatchd.service pkcs11-daemon.service xfs_healer@.service order368-other.service order368-other@.service stafd.service; do
 cat >"/etc/systemd/system/$unit" <<'UNIT'
[Unit]
Description=ORDER 368 forced failure %n
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo ORDER368 forced failure; exit 42'
UNIT
done
systemctl daemon-reload
for u in "${units[@]}"; do
 systemctl reset-failed "$u" 2>/dev/null || true
 $B clear --machine sparky-stereo-service-defaults "$u"
 $B clear --boot sparky-stereo-problems "$u"
done
# IPwatchD's real condition needs a global IPv4; a missing prerequisite is NOT a red.
ip -4 -o address show scope global | grep .
loginctl enable-linger "$PERSON"
waitfor test -S "/run/user/$U/bus"
install -m 755 "${1:?fake-notifications.py}" /usr/local/bin/order368-notifications
ux systemd-run --user --quiet --unit fake-notifications /usr/local/bin/order368-notifications "$H/notify.json"
waitfor ux busctl --user status org.freedesktop.Notifications
ux $B list --json >"$E/before.json"
python3 - "$E/before.json" <<'PY' >"$E/hide.tsv"
import json,sys
for p in json.load(open(sys.argv[1])):
    if not p.get('hidden'): print(p['scope'], p['package'], p['key'], sep='\t')
PY
while IFS=$'\t' read -r scope package key; do ux "$B" hide "--$scope" "$package" "$key"; done <"$E/hide.tsv"
ux systemctl --user start sparky-stereo-problems-notifier.service
waitfor test -f "/run/user/$U/sparky-stereo-problems/notified"
sleep 1
# No login summary: the notifier is running before each newly forced failure.
for u in "${units[@]}"; do
 systemctl show "$u" -p OnFailure -p DropInPaths >"$E/$u.handlers"
 set +e
 systemctl start "$u" >"$E/$u.start" 2>&1
 rc=$?
 set -e
 echo "$rc" >"$E/$u.start.exit"
 [ "$rc" = 1 ]
 [ "$(systemctl show "$u" -p ExecMainStatus --value)" = 42 ]
 # Wait for all handlers to complete, then for the notifier's 300ms settle timer.
 for ((j=0;j<60;j++)); do
  jobs=$(systemctl list-jobs --no-legend)
  if ! [[ "$jobs" == *sparky-stereo* ]]; then break; fi
  sleep 0.25
 done
 sleep 2
 ux "$B" list --json >"$E/$u.records.json"
 cp "$H/notify.json" "$E/$u.notices.json"
done
cp "$H/notify.json" "$E/notices.json"
ux "$B" list --json >"$E/records.json"
python3 - "$E" "${units[@]}" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); rows=[]; errors=0
records=json.load(open(p/'records.json')); previous=0
for u in sys.argv[2:]:
    rs=[r for r in records if r['key']==u and not r['hidden']]
    notices=json.load(open(p/f'{u}.notices.json'))['notify']
    ns=notices[previous:]; previous=len(notices)
    own=u.split('@')[0] in ('xfs_healer',) or u in ('urfkill.service','snmptt.service','ipwatchd.service','pkcs11-daemon.service')
    expected='sparky-stereo-service-defaults' if own else 'sparky-stereo-problems'
    good=len(rs)==len(ns)==1 and rs[0]['package']==expected and rs[0]['repair']==[['systemctl','restart',u]] and 'Repair' in ns[0]['actions'] and u.split('.service')[0].split('@')[0] in ns[0]['body']
    rows.append(f'{"PASS" if good else "FAIL"} {u}: records={len(rs)} notices={len(ns)} packages={[r["package"] for r in rs]}')
    errors+=not good
text='\n'.join(rows)+f'\nfailures: {errors}\n'
(p/'counts.txt').write_text(text); print(text,end='')
sys.exit(bool(errors))
PY
