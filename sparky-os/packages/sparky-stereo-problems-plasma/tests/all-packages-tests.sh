#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Every package that hands its failures to the engine, installed together under a real systemd user manager (systemd as
# PID 1, a person with linger, polkit; run session-tests.sh first, which sets up the person, the stand-in notification
# server and the kdialog stand-in): each keeps a problem through its own command, a new login shows them in one
# notification, and each package's own dismiss hides its problem the same way (the engine's Hide, the person's).
# Run as root. Usage: all-packages-tests.sh
set -u
fail=0
ok() { echo "PASS  $1"; }
no() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
waitfor() { local i; for i in $(seq 1 "${2:-20}"); do eval "$1" && return 0; sleep 0.5; done; return 1; }
B=sparky-stereo-problems
U=$(id -u person)
H=/home/person
LOG=$H/notify.json
ux() { runuser -u person -- env HOME=$H XDG_RUNTIME_DIR=/run/user/$U DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$U/bus "$@"; }
n() { python3 -c "import json; print(len(json.load(open('$LOG'))['notify']))" 2>/dev/null || echo 0; }
nf() { python3 -c "import json,sys; d=json.load(open('$LOG'))['notify']; print(d[-1][sys.argv[1]])" "$1" 2>/dev/null; }
mine() { ux $B list --json | python3 -c "import json,sys; print(sorted((p['package'], p['key'], p['hidden']) for p in json.load(sys.stdin) if p.get('key') in sys.argv[1:]))" "$@"; }

# a stand-in notification server of this test's own (session-tests.sh stops its own when it ends)
install -m 755 /suite-plasma/fake-notifications.py /usr/local/bin/fake-notifications
ux systemctl --user stop fake-notifications.service 2>/dev/null
ux systemd-run --user --quiet --unit fake-notifications-all /usr/local/bin/fake-notifications $LOG
check "a notification server answers" "waitfor 'ux busctl --user status org.freedesktop.Notifications >/dev/null 2>&1' 30"

echo "== start from nothing kept"
ux systemctl --user stop sparky-stereo-problems-notifier.service 2>/dev/null
rm -f /var/lib/sparky-stereo-problems/*.json /run/sparky-stereo-problems/*.json $H/.local/state/sparky-stereo-problems/*.json
rm -rf $H/.local/state/sparky-stereo-problems/.hidden /run/user/$U/sparky-stereo-problems/notified
check "nothing is kept" "[ -z \"\$($B list --json | python3 -c 'import json,sys; print(json.load(sys.stdin) or \"\")')\" ]"

echo "== each package keeps a problem through its own command"
python3 /usr/lib/sparky-stereo-boot/problems.py record all-boot LOCAL21 update-grub 1 2>/dev/null
python3 /usr/lib/sparky-stereo-time/problems.py record all-time LOCAL10 /usr/share/sparky-stereo-time/ntp-countries.tsv 'No such file or directory' 2>/dev/null
python3 /usr/lib/sparky-stereo-service-defaults/problems.py record all-sd LOCAL1 ipwatchd.service 'it broke' 2>/dev/null
python3 - <<'EOP' 2>/dev/null
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader('dpkg_stereo', '/usr/sbin/dpkg-stereo')
spec = importlib.util.spec_from_loader('dpkg_stereo', loader)
m = importlib.util.module_from_spec(spec)
sys.argv = ['dpkg-stereo']
loader.exec_module(m)
m.keep_problem(m.Paths('/'), 'project', 'NotADirectoryError: /var/lib/dpkg-stereo/records', quiet=True)
EOP
$B keep --boot --quiet --severity failed sparky-stereo-cushion-swap no-area LOCAL1
$B run --machine --quiet sparky-stereo-grub-l10n update-grub LOCAL21 -- sh -c 'echo "grub-mkconfig: fake failure" >&2; exit 1' 2>/dev/null
ux mkdir -p $H/.config
printf '[General]\nMainGpu=pci-0000:09:00.0\n' >$H/.config/sparky-stereo-graphicsrc; chown person $H/.config/sparky-stereo-graphicsrc
ux sparky-stereo-gpu-env --session >/dev/null 2>&1
check "seven packages, seven problems, each kept by the engine" "[ \"\$($B list --json | python3 -c 'import json,sys; print(len({p[\"package\"] for p in json.load(sys.stdin)}))')\" = 7 ] || [ \"\$(ux $B list --json | python3 -c 'import json,sys; print(len({p[\"package\"] for p in json.load(sys.stdin)}))')\" = 7 ]"
check "the person sees all seven, each in English as the package says it" "ux env LANG=C.UTF-8 $B list | grep -c '^failed' | grep -qx 7"

echo "== one notification at login for the problems of every package"
c=$(n)
ux systemctl --user start sparky-stereo-problems-notifier.service
check "one notification" "waitfor '[ \$(n) -gt $c ]' 30 && sleep 3 && [ \$(n) = $((c + 1)) ]"
check "the summary of the seven" "[ \"\$(nf summary)\" = '7 problems need attention' ]"
check "a line for each package's problem" "nf body | grep -q 'sparky-stereo-boot is not configured' && nf body | grep -q 'time-server catalogue' && nf body | grep -q 'ipwatchd.service' && nf body | grep -q 'did not complete' && nf body | grep -q 'Cushion Swap' && nf body | grep -q 'sparky-stereo-grub-l10n is not configured' && nf body | grep -q 'is not in this computer now'"

echo "== each package's own dismiss is the engine's Hide, the person's"
ux sparky-stereo-boot dismiss all-boot >/dev/null 2>&1
ux sparky-stereo-time --dismiss all-time >/dev/null 2>&1
ux sparky-stereo-service-defaults dismiss all-sd >/dev/null 2>&1
ux dpkg-stereo --dismiss project >/dev/null 2>&1
ux $B hide --boot sparky-stereo-cushion-swap no-area
ux $B hide --machine sparky-stereo-grub-l10n update-grub
ux $B hide --person sparky-stereo-graphics main-gpu
check "hidden for the person, each package's the same way" "[ \"\$(mine all-boot all-time all-sd project no-area update-grub main-gpu)\" = \"[('dpkg-stereo', 'project', True), ('sparky-stereo-boot', 'all-boot', True), ('sparky-stereo-cushion-swap', 'no-area', True), ('sparky-stereo-graphics', 'main-gpu', True), ('sparky-stereo-grub-l10n', 'update-grub', True), ('sparky-stereo-service-defaults', 'all-sd', True), ('sparky-stereo-time', 'all-time', True)]\" ]"
check "and still listed for root, not hidden" "[ \"\$($B list --json | python3 -c 'import json,sys; print(sum(1 for p in json.load(sys.stdin) if not p[\"hidden\"]))')\" = 6 ]"
ux systemctl --user stop sparky-stereo-problems-notifier.service
rm -f /run/user/$U/sparky-stereo-problems/notified
c=$(n)
ux systemctl --user start sparky-stereo-problems-notifier.service
sleep 4
check "a new login shows nothing hidden" "[ \$(n) = $c ]"
python3 /usr/lib/sparky-stereo-time/problems.py record all-time LOCAL10 /usr/share/sparky-stereo-time/ntp-countries.tsv 'Permission denied' 2>/dev/null
check "a hidden problem whose message changes comes back, for any package" "waitfor '[ \$(n) = $((c + 1)) ]' 20 && nf body | grep -q 'Permission denied'"

echo "== a package removed: its problems go"
dpkg -r sparky-stereo-time >/tmp/remove-time.log 2>&1
check "the time package's problems went with it" "[ -z \"\$(ls /var/lib/sparky-stereo-problems/ | grep sparky-stereo-time)\" ]"
check "the others stay" "[ -e /var/lib/sparky-stereo-problems/sparky-stereo-boot_all-boot.json ]"

ux systemctl --user stop sparky-stereo-problems-notifier.service fake-notifications-all.service 2>/dev/null
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
