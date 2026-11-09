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

echo "== Dismiss a failed service: it stays dismissed when it fails the same way at the next boot (ORDER 468)"
id person >/dev/null 2>&1 || useradd -m person
asp() { runuser -u person -- env -i HOME=/home/person PATH=/usr/bin:/bin "$@"; }
systemctl start failer.service 2>/dev/null
check "the service fails: kept for this boot" "waitfor '[ -f $R ]' 30"
old=$(python3 -c "import json; print(json.load(open('$R'))['id'])")
asp $B hide --boot $P failer.service
asp $B list --json >/tmp/p1.json
check "the person dismisses it" "python3 -c \"import json,sys; d=[p for p in json.load(open('/tmp/p1.json')) if p['key'] == 'failer.service']; sys.exit(0 if d and d[0]['hidden'] else 1)\""
# the next boot: systemd has no failed unit and /run is empty again (a reboot cannot be had inside this container)
systemctl reset-failed failer.service
$B list >/dev/null
rm -f $R
asp $B list --json --over >/tmp/p2.json
check "until it fails again it is listed as dismissed and not happening now" "python3 -c \"import json,sys; d=[p for p in json.load(open('/tmp/p2.json')) if p['key'] == 'failer.service']; sys.exit(0 if d and d[0]['hidden'] and d[0]['over'] else 1)\""
systemctl start failer.service 2>/dev/null
check "it fails the same way: a new record" "waitfor '[ -f $R ]' 30 && [ \"\$(python3 -c \"import json; print(json.load(open('$R'))['id'])\")\" != \"$old\" ]"
asp $B list --json >/tmp/p3.json
check "and the person does not see it again: dismissed" "python3 -c \"import json,sys; d=[p for p in json.load(open('/tmp/p3.json')) if p['key'] == 'failer.service']; sys.exit(0 if d and d[0]['hidden'] and not d[0]['over'] else 1)\""
$B list --json >/tmp/r3.json
check "for root it is not dismissed: the mark is the person's" "python3 -c \"import json,sys; d=[p for p in json.load(open('/tmp/r3.json')) if p['key'] == 'failer.service']; sys.exit(0 if d and not d[0]['hidden'] else 1)\""
mkdir -p /etc/systemd/system/failer.service.d
printf '[Service]\nExecStart=\nExecStart=/bin/sh -c "exit 4"\n' >/etc/systemd/system/failer.service.d/other.conf
systemctl daemon-reload
systemctl reset-failed failer.service
$B list >/dev/null
rm -f $R
systemctl start failer.service 2>/dev/null
check "it fails with another exit status (4): a new record" "waitfor '[ -f $R ]' 30 && pyck $R 'd[\"args\"][2] == [\"LOCAL5\", \"4\"]'"
asp $B list --json >/tmp/p4.json
check "and the person does not see it: the same service is still dismissed" "python3 -c \"import json,sys; d=[p for p in json.load(open('/tmp/p4.json')) if p['key'] == 'failer.service']; sys.exit(0 if d and d[0]['hidden'] else 1)\""
asp $B show --boot $P failer.service
rm -f /etc/systemd/system/failer.service.d/other.conf
systemctl daemon-reload
systemctl reset-failed failer.service

echo "== a failed hibernation says why (ORDER 446); the attempt's lines are written by a unit that logs as systemd-sleep"
# the real systemd-sleep needs a kernel to hibernate; these units log what it logs (SyslogIdentifier, the <3> priority
# prefix) and end as it ends. The kernel's own lines are read from a fixture in sleep-tests.sh: no kernel is asked here
SLEEPERR='<3>Failed to find location to hibernate to: No space left on device'
fakesleep() {
	mkdir -p /etc/systemd/system/$1.d
	printf '[Service]\nType=oneshot\nSyslogIdentifier=systemd-sleep\nExecStart=\nExecStart=/bin/sh -c "echo \\"%s\\"; exit %s"\n' "$SLEEPERR" "$2" >/etc/systemd/system/$1.d/zz-fake.conf
}
HIB=systemd-hibernate.service
STH=systemd-suspend-then-hibernate.service
fakesleep $HIB 1
systemctl daemon-reload
check "the top-level drop-in names the handler for the sleep unit" "systemctl show -p OnFailure $HIB | grep -qx 'OnFailure=sparky-stereo-problems-failed@$HIB'"
systemctl start $HIB 2>/dev/null
H=$RUN/${P}_$HIB.json
check "a failed hibernation is kept for this boot by the handler" "waitfor '[ -f $H ]' 30"
check "it says what could not be done and why, from the attempt's own journal line, not only that the service failed" "pyck $H 'd[\"message\"] == \"LOCAL72\" and d[\"args\"][1][0] == \"LOCAL81\" and \"No space left on device\" in d[\"args\"][1][1]'"
check "the problem is shown with the reason and what to do" "$B list | grep -qF 'The computer could not hibernate: no swap area is big enough for the memory image (Failed to find location to hibernate to: No space left on device). Make the swap area'"
check "it does not say that Repair starts it again, and it offers no repair for a cause that stays" "! $B text --boot $P $HIB | grep -qF 'Repair starts it again' && pyck $H 'd[\"repair\"] == []'"
journalctl --sync 2>/dev/null
SID=$($B message-id $P LOCAL72)
check "the event is in the journal with the message's MESSAGE_ID and the reason as fields" "journalctl -o json MESSAGE_ID=\$SID | python3 -c 'import json,sys; e=[json.loads(l) for l in sys.stdin]; sys.exit(0 if any(x.get(\"SPARKY_PROBLEM_KEY\") == \"$HIB\" and x.get(\"SPARKY_ARG_A\") == \"hibernate\" and \"No space\" in x.get(\"SPARKY_ARG_B\", \"\") for x in e) else 1)'"
check "journalctl -x explains it from the catalog" "journalctl -x MESSAGE_ID=\$SID --no-pager | grep -q 'The computer could not hibernate: no swap area is big enough'"
LANG=de_DE.UTF-8 journalctl -x MESSAGE_ID=\$SID --no-pager >/tmp/x-sleep-de.txt 2>&1
check "and in German from the German catalog (its arguments are the journal's fields, in English: journalctl -x fills them in)" "grep -q 'Der Computer konnte nicht hibernate: ' /tmp/x-sleep-de.txt"
printf '[Service]\nExecStart=\nExecStart=/bin/true\n' >/etc/systemd/system/$HIB.d/zz-fake.conf
systemctl daemon-reload
systemctl start $HIB 2>/dev/null
$B list >/dev/null
check "a hibernation that works again ends it (systemd no longer has the unit as failed)" "[ ! -f $H ]"
rm -rf /etc/systemd/system/$HIB.d
systemctl daemon-reload
systemctl reset-failed $HIB 2>/dev/null

echo "== suspend-then-hibernate that falls back to suspending ends well: its ExecStopPost still tells"
check "the package's drop-in runs the engine after the service" "systemctl show -p ExecStopPost $STH | grep -q 'sparky-stereo-problems sleep-attempt'"
check "the same for hybrid sleep" "systemctl show -p ExecStopPost systemd-hybrid-sleep.service | grep -q 'sparky-stereo-problems sleep-attempt'"
fakesleep $STH 0
systemctl daemon-reload
systemctl start $STH 2>/dev/null
S=$RUN/${P}_$STH.json
check "the service ended well (no OnFailure ran) and the failed hibernation is kept" "systemctl is-failed --quiet $STH; [ \$? != 0 ] && waitfor '[ -f $S ]' 30"
check "with the reason and no unit, so no unit state can end it early" "pyck $S 'd[\"args\"][1][0] == \"LOCAL81\" and d.get(\"unit\") is None'"
check "it stays listed after the unit went inactive" "$B list | grep -qF 'The computer could not hibernate after suspending: no swap area is big enough'"
printf '[Service]\nExecStart=\nExecStart=/bin/true\n' >/etc/systemd/system/$STH.d/zz-fake.conf
systemctl daemon-reload
systemctl start $STH 2>/dev/null
check "the next attempt that works ends it" "waitfor '[ ! -f $S ]' 30"
rm -rf /etc/systemd/system/$STH.d
systemctl daemon-reload

echo "== the stores keep their own entries only (a flat store)"
check "no subfolder and no dot-file is left in the machine's store" "[ -z \"\$(find /var/lib/sparky-stereo-problems -mindepth 1 -not -name .lock -name '.*')\" ] && [ -z \"\$(find /var/lib/sparky-stereo-problems -mindepth 1 -type d)\" ]"

systemctl reset-failed failer@x.service 2>/dev/null
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
