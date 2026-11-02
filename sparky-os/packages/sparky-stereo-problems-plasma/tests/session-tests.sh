#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# The notifier under a real systemd user manager (systemd as PID 1, a person with linger, their session bus, polkit),
# sparky-stereo-problems and sparky-stereo-problems-plasma installed, a stand-in notification server
# (fake-notifications.py) in the person's manager. Run as root. Usage: session-tests.sh SUITE_DIR
set -u
fail=0
ok() { echo "PASS  $1"; }
no() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
waitfor() { local i; for i in $(seq 1 "${2:-20}"); do eval "$1" && return 0; sleep 0.5; done; return 1; }
SUITE=$1
B=sparky-stereo-problems
P=sparky-stereo-problems
id person >/dev/null 2>&1 || useradd -m person
U=$(id -u person)
H=/home/person
LOG=$H/notify.json
ux() { runuser -u person -- env HOME=$H XDG_RUNTIME_DIR=/run/user/$U DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus "$@"; }
n() { python3 -c "import json,sys; d=json.load(open('$LOG')); print(len(d['notify']))" 2>/dev/null || echo 0; }
# the Nth notification's field (1 = first), or the last one with -1
nf() { python3 -c "import json,sys; d=json.load(open('$LOG'))['notify']; print(d[int(sys.argv[1]) - 1 if int(sys.argv[1]) > 0 else -1][sys.argv[2]])" "$1" "$2" 2>/dev/null; }
closed() { python3 -c "import json,sys; d=json.load(open('$LOG')); sys.exit(0 if int(sys.argv[1]) in d['closed'] else 1)" "$1" 2>/dev/null; }
invoke() { ux busctl --user call org.freedesktop.Notifications /test org.sparkylinux.Test Invoke us "$1" "$2" >/dev/null; }

echo "== the person's session"
loginctl enable-linger person
check "the person's user manager runs" "waitfor '[ -S /run/user/$U/bus ] && ux systemctl --user is-system-running --quiet --wait 2>/dev/null; ux systemctl --user is-system-running 2>/dev/null | grep -qE \"running|degraded\"' 60"
install -m 755 "$SUITE/fake-notifications.py" /usr/local/bin/fake-notifications
ux systemd-run --user --quiet --unit fake-notifications /usr/local/bin/fake-notifications $LOG
check "a notification server answers on the person's bus" "waitfor 'ux busctl --user status org.freedesktop.Notifications >/dev/null 2>&1' 30"
# kdialog stand-in: what Show details opens, written down
cat >/usr/local/bin/kdialog <<'EOS'
#!/bin/sh
{ echo "ARGS: $*"; cat "$4"; } > "$HOME/kdialog.log"
EOS
chmod 755 /usr/local/bin/kdialog
check "the units are enabled for the person's graphical session" "[ -L /usr/lib/systemd/user/graphical-session.target.wants/sparky-stereo-problems-notifier.service ] && [ -L /usr/lib/systemd/user/graphical-session.target.wants/sparky-stereo-problems-notifier.path ]"

echo "== at login: several open problems, one summary"
$B keep --machine $P one LOCAL4 "First Service" one.service @LOCAL8 --repair '["true"]'
$B keep --machine $P two LOCAL4 "Second Service" two.service @LOCAL9
ux systemctl --user start sparky-stereo-problems-notifier.path sparky-stereo-problems-notifier.service
check "the notifier runs under the person's manager" "waitfor 'ux systemctl --user is-active --quiet sparky-stereo-problems-notifier.service' 20"
check "the path unit watches the stores" "ux systemctl --user is-active --quiet sparky-stereo-problems-notifier.path"
check "one notification at login" "waitfor '[ \$(n) = 1 ]' 30 && sleep 2 && [ \$(n) = 1 ]"
check "it is the summary of the two, a line each" "[ \"\$(nf 1 summary)\" = '2 problems need attention' ] && nf 1 body | grep -q '• The system service First Service (one.service) failed' && nf 1 body | grep -q '• The system service Second Service (two.service) failed'"
check "critical, because a problem failed, and it stays (no timeout)" "[ \"\$(nf 1 urgency)\" = 2 ] && [ \"\$(nf 1 timeout)\" = 0 ]"
check "it offers Show details" "nf 1 actions | grep -q 'Show details'"
invoke 1 "Show details"
check "Show details opens one notification per problem" "waitfor '[ \$(n) = 3 ]' 20"
check "each with its own buttons: Show details, Repair (when it has one), Hide" "nf 2 actions | grep -q \"'Repair'\" && nf 2 actions | grep -q \"'Hide'\" && ! nf 3 actions | grep -q \"'Repair'\""
check "each says what failed and why" "nf 2 body | grep -q 'The system service First Service (one.service) failed: it did not finish in time'"

echo "== then one notification per new or changed problem"
$B keep --machine $P three LOCAL4 "Third Service" three.service @LOCAL10
check "a new problem: one notification" "waitfor '[ \$(n) = 4 ]' 20 && [ \"\$(nf 4 summary)\" = 'Sparky Stereo OS: a system service failed' ] && nf 4 body | grep -q 'Third Service'"
$B keep --machine $P three LOCAL4 "Third Service" three.service @LOCAL10
sleep 3
check "kept again with the same message: no new notification" "[ \$(n) = 4 ]"
$B keep --machine $P three LOCAL4 "Third Service" three.service @LOCAL11
check "a changed message: one new notification" "waitfor '[ \$(n) = 5 ]' 20 && nf 5 body | grep -q 'its watchdog stopped hearing from it'"
check "and the old one is closed" "closed 4"
$B keep --machine --severity degraded $P part LOCAL4 "Partial" p.service @LOCAL8
check "a degraded problem is Normal and times out" "waitfor '[ \$(n) = 6 ]' 20 && [ \"\$(nf 6 urgency)\" = 1 ] && [ \"\$(nf 6 timeout)\" = -1 ]"

echo "== Show details, Hide"
invoke 5 "Show details"
check "Show details shows the evidence (kdialog --textbox)" "waitfor '[ -s $H/kdialog.log ]' 20 && grep -q 'ARGS: --title Sparky Stereo OS: a system service failed --textbox' $H/kdialog.log && grep -q 'Kept since: ' $H/kdialog.log && grep -q 'Kept in: /var/lib/sparky-stereo-problems/sparky-stereo-problems_three.json' $H/kdialog.log"
invoke 6 "Hide"
check "Hide hides it for the person" "waitfor 'ux $B list --json | python3 -c \"import json,sys; sys.exit(0 if any(p[\\\"key\\\"] == \\\"part\\\" and p[\\\"hidden\\\"] for p in json.load(sys.stdin)) else 1)\"' 20"
check "and not for root" "$B list --json | python3 -c 'import json,sys; sys.exit(0 if any(p[\"key\"] == \"part\" and not p[\"hidden\"] for p in json.load(sys.stdin)) else 1)'"
c=$(n)
$B keep --machine --severity degraded $P part LOCAL4 "Partial" p.service @LOCAL8
sleep 3
check "a hidden problem kept again with the same message: no notification" "[ \$(n) = $c ]"
$B keep --machine --severity degraded $P part LOCAL4 "Partial" p.service @LOCAL9
check "it comes back when its message changes" "waitfor '[ \$(n) = $((c + 1)) ]' 20 && nf -1 body | grep -q 'started too often'"

echo "== Repair"
ux $B keep $P mine LOCAL4 "Mine" m.service @LOCAL8 --repair '["true"]'
check "the person's own problem: one notification" "waitfor 'nf -1 body | grep -q \"Mine (m.service)\"' 20"
c=$(n)
invoke $c "Repair"
check "Repair of the person's problem runs as the person: it is over" "waitfor '[ ! -e $H/.local/state/sparky-stereo-problems/${P}_mine.json ]' 20"
check "and that is said: It works again" "waitfor '[ \"\$(nf -1 summary)\" = \"It works again\" ]' 20"
check "its notification is closed" "closed $c"
mkdir -p /etc/polkit-1/rules.d
cat >/etc/polkit-1/rules.d/50-problems-test.rules <<'EOS'
polkit.addRule(function(action, subject) {
    if (action.id == "org.sparkylinux.problems.repair" && subject.user == "person") { return polkit.Result.YES; }
});
EOS
systemctl restart polkit.service 2>/dev/null
check "polkit knows the action, with pkexec's program and argv1" "pkaction --verbose --action-id org.sparkylinux.problems.repair | grep -q 'org.freedesktop.policykit.exec.argv1 -> repair'"
first=$(python3 -c "import json; d=json.load(open('$LOG'))['notify']; print([x['id'] for x in d if 'First Service' in x['body'] and \"'Repair'\" in str(x['actions'])][-1])")
invoke "$first" "Repair"
check "Repair of the machine's problem runs through pkexec as root: it is over" "waitfor '[ ! -e /var/lib/sparky-stereo-problems/${P}_one.json ]' 30"
check "and that is said" "waitfor '[ \"\$(nf -1 summary)\" = \"It works again\" ] && nf -1 body | grep -q \"a system service failed\"' 20"
rm /etc/polkit-1/rules.d/50-problems-test.rules
systemctl restart polkit.service 2>/dev/null
$B keep --machine $P four LOCAL4 "Fourth Service" four.service @LOCAL8 --repair '["true"]'
waitfor 'nf -1 body | grep -q "Fourth Service"' 20
invoke "$(n)" "Repair"
check "without the administrator's permission the repair does not run, and that is said" "waitfor '[ \"\$(nf -1 summary)\" = \"The repair did not run\" ]' 30 && nf -1 body | grep -q 'pkexec exit status 12[67]'"
check "and the problem stays" "[ -e /var/lib/sparky-stereo-problems/${P}_four.json ]"

echo "== a problem's own action"
ux $B keep $P act LOCAL4 "Act" a.service @LOCAL8 --action '{"id":"touch","label":["LOCAL23","touch the file"],"command":["touch","'$H'/action-ran"]}'
check "its label is a button" "waitfor 'nf -1 actions | grep -q \"Repair: touch the file\"' 20"
invoke "$(n)" "Repair: touch the file"
check "the button runs its command as the person" "waitfor '[ -e $H/action-ran ] && [ \$(stat -c %U $H/action-ran) = person ]' 20"

echo "== a problem that is over closes its notification"
last=$(n)
$B clear --machine $P four
check "cleared: its notification closes" "waitfor 'closed $last' 20"

echo "== the path unit starts the notifier"
ux systemctl --user stop sparky-stereo-problems-notifier.service
c=$(n)
$B keep --machine $P five LOCAL4 "Fifth Service" five.service @LOCAL8
check "a problem kept while the notifier is stopped starts it" "waitfor 'ux systemctl --user is-active --quiet sparky-stereo-problems-notifier.service' 20"
check "and it is shown" "waitfor 'nf -1 body | grep -q \"Fifth Service\"' 20"

echo "== a failed system service reaches the person"
cat >/etc/systemd/system/failer2.service <<'EOS'
[Unit]
Description=Second failer for the session
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo no network for the session test; exit 4'
EOS
systemctl daemon-reload
systemctl start failer2.service 2>/dev/null
check "a failed system service is notified, with what systemd says" "waitfor 'nf -1 body | grep -q \"Second failer for the session (failer2.service) failed: it stopped with exit status 4\"' 30"
systemctl reset-failed failer2.service
check "and when systemd no longer has it as failed, its notification closes" "waitfor 'closed $(n)' 30"

echo "== in German"
ux systemctl --user stop sparky-stereo-problems-notifier.service sparky-stereo-problems-notifier.path
rm -f /run/user/$U/sparky-stereo-problems/notified
ux systemctl --user set-environment LANG=de_DE.UTF-8
c=$(n)
ux systemctl --user start sparky-stereo-problems-notifier.service
check "a new login shows the open problems again, in German" "waitfor '[ \$(n) -gt $c ]' 20 && nf -1 summary | grep -q 'Probleme brauchen Aufmerksamkeit' && nf -1 actions | grep -q 'Details anzeigen'"
ux systemctl --user unset-environment LANG

ux systemctl --user stop sparky-stereo-problems-notifier.service fake-notifications.service 2>/dev/null
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
