#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# The engine under a real systemd (PID 1, journald, the system bus), as root, sparky-stereo-problems installed: the
# failed-service drop-in and its handler with systemd's own $MONITOR_* variables, the service's last lines from the
# journal, the journal's MESSAGE_ID and catalogs (journalctl -x, in German too), the repair by restart, and the
# problem that is over when systemd no longer has the unit as failed. Usage: systemd-tests.sh
set -u
fail=0
ok() { echo "PASS  $1"; }
no() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
waitfor() { local i; for i in $(seq 1 "${2:-20}"); do eval "$1" && return 0; sleep 0.5; done; return 1; }
pyck() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if ($2) else 1)" "$1" 2>/dev/null; }
B=sparky-stereo-problems
P=sparky-stereo-problems
RUN=/run/sparky-stereo-problems
ID=$($B message-id $P LOCAL4)

echo "== installed"
check "the package configured without a problem of its own" "[ -z \"\$($B list --json | python3 -c 'import json,sys; print([p for p in json.load(sys.stdin) if p.get(\"package\") == \"$P\"] or \"\")')\" ]"
check "systemd-tmpfiles made both stores" "[ -d /var/lib/sparky-stereo-problems ] && [ -d $RUN ]"

echo "== every failed system service is told"
cat >/etc/systemd/system/failer.service <<'EOS'
[Unit]
Description=Failer for the test
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo failer says the disk is gone; exit 3'
EOS
cat >/etc/systemd/system/failer@.service <<'EOS'
[Unit]
Description=Templated failer %i
[Service]
Type=oneshot
ExecStart=/bin/false
EOS
systemctl daemon-reload
check "the top-level drop-in names the handler for a service" "systemctl show -p OnFailure failer.service | grep -qx 'OnFailure=sparky-stereo-problems-failed@failer.service'"
check "and for a template's instance" "systemctl show -p OnFailure failer@x.service | grep -qx 'OnFailure=sparky-stereo-problems-failed@failer@x.service'"
check "the handler's own instances have it masked (no recursion)" "systemctl show -p OnFailure sparky-stereo-problems-failed@failer.service | grep -qx 'OnFailure='"
systemctl start failer.service 2>/dev/null
R=$RUN/${P}_failer.service.json
check "a failing service is kept for this boot by the handler" "waitfor '[ -f $R ]' 30"
check "with systemd's result as words: exit status 3" "pyck $R 'd[\"args\"][2] == [\"LOCAL5\", \"3\"] and d[\"status\"] == 3'"
check "with the unit's own Description from systemd" "pyck $R 'd[\"args\"][0] == \"Failer for the test\" and d[\"unit\"] == \"failer.service\"'"
check "with the service's own last lines from the journal" "pyck $R '\"failer says the disk is gone\" in d[\"output\"]'"
check "with systemctl restart as its repair" "pyck $R 'd[\"repair\"] == [[\"systemctl\", \"restart\", \"failer.service\"]]'"
check "the handler itself succeeded" "systemctl is-failed --quiet sparky-stereo-problems-failed@failer.service; [ \$? != 0 ]"
check "said in list" "$B list | grep -q 'The system service Failer for the test (failer.service) failed: it stopped with exit status 3'"

echo "== the journal"
journalctl --sync 2>/dev/null
check "the event is in the journal with the message's MESSAGE_ID and its fields" "journalctl -o json MESSAGE_ID=$ID | python3 -c 'import json,sys; e=[json.loads(l) for l in sys.stdin]; sys.exit(0 if any(x.get(\"SPARKY_PROBLEM_KEY\") == \"failer.service\" and x.get(\"SPARKY_ARG_B\") == \"failer.service\" and x.get(\"PRIORITY\") == \"3\" for x in e) else 1)'"
check "journalctl -x explains it from the catalog, with the problem's own fields" "journalctl -x MESSAGE_ID=$ID --no-pager | grep -q '^░░ The system service Failer for the test (failer.service) failed: it stopped with exit status 3'"
LANG=de_DE.UTF-8 journalctl -x MESSAGE_ID=$ID --no-pager >/tmp/x-de.txt 2>&1
check "journalctl -x explains it in German from the German catalog" "grep -q '^░░ Der Systemdienst Failer for the test (failer.service) ist fehlgeschlagen' /tmp/x-de.txt"

echo "== a template's instance"
systemctl start failer@x.service 2>/dev/null
check "an instance of a template is told too" "waitfor '[ -f $RUN/${P}_failer@x.service.json ]' 30"
check "with its own Description" "pyck $RUN/${P}_failer@x.service.json 'd[\"args\"][0] == \"Templated failer x\"'"

echo "== repair, and the problem that is over"
mkdir -p /etc/systemd/system/failer.service.d
printf '[Service]\nExecStart=\nExecStart=/bin/true\n' >/etc/systemd/system/failer.service.d/fixed.conf
systemctl daemon-reload
$B repair --boot $P failer.service >/tmp/rep.out 2>&1; rc=$?
check "repair restarts the service; it works, so the problem goes (exit 0)" "[ $rc = 0 ] && [ ! -f $R ]"
check "the repair is in the journal" "journalctl -o json MESSAGE_ID=$($B message-id $P LOCAL13) | grep -q failer.service"
rm /etc/systemd/system/failer.service.d/fixed.conf
systemctl daemon-reload
systemctl start failer.service 2>/dev/null
check "failing again, it is kept again" "waitfor '[ -f $R ]' 30"
systemctl reset-failed failer.service
$B list >/tmp/list.out
check "when systemd no longer has it as failed, it is over: not listed" "! grep -q 'failer.service) failed' /tmp/list.out"
check "and its record goes" "[ ! -f $R ]"
check "that is in the journal too" "journalctl -o json MESSAGE_ID=$($B message-id $P LOCAL21) | grep -q failer.service"

echo "== the stores keep their own entries only (a flat store)"
check "no subfolder and no dot-file is left in the machine's store" "[ -z \"\$(find /var/lib/sparky-stereo-problems -mindepth 1 -not -name .lock -name '.*')\" ] && [ -z \"\$(find /var/lib/sparky-stereo-problems -mindepth 1 -type d)\" ]"

systemctl reset-failed failer@x.service 2>/dev/null
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
