#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Root in a disposable systemd/polkit container, with runtime dependencies of the old Plasma package installed.
# Arguments: old engine deb, old Plasma deb, new engine deb, new Plasma deb, Plasma test directory.
set -eu
OLD=$1; OLD_PLASMA=$2; NEW=$3; NEW_PLASMA=$4; SUITE=$5
P=sparky-stereo-problems
B=/usr/bin/$P
id person >/dev/null 2>&1 || useradd -m -G sudo person
mkdir -p /opt/pe661-upgrade
chmod 777 /opt/pe661-upgrade
rm -f /opt/pe661-upgrade/{ready,upgraded,result,notify.json,notify.json.tmp} /run/pe661-upgrade-repaired
systemctl reset-failed
$B clear --all "$P"
dpkg --force-downgrade -i "$OLD" "$OLD_PLASMA"
cat >/etc/polkit-1/rules.d/00-pe661.rules <<'EOS'
polkit.addRule(function(action, subject) {
    if (subject.user == "person") {
        if (action.id == "org.freedesktop.policykit.exec") return polkit.Result.AUTH_ADMIN;
        if (action.id == "org.sparkylinux.sparkystereo.problems.repair") return polkit.Result.AUTH_ADMIN_KEEP;
    }
});
EOS
systemctl restart polkit
$B keep --machine "$P" before-upgrade LOCAL4 "Before Upgrade" before.service @LOCAL8 --repair '["/usr/bin/touch","/run/pe661-upgrade-repaired"]'
install -m 755 "$SUITE/fake-notifications.py" /opt/pe661-upgrade/fake-notifications
cat >/opt/pe661-upgrade/person <<'EOS'
#!/bin/bash
set -eu
D=/opt/pe661-upgrade
export QT_QPA_PLATFORM=offscreen
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export LANG=C.UTF-8
waitfor() { for i in $(seq 1 150); do if eval "$1"; then return 0; fi; sleep 0.2; done; return 1; }
"$D/fake-notifications" "$D/notify.json" >"$D/server.log" 2>&1 & server=$!
notifier=0; agent=0
trap 'for p in "$agent" "$notifier" "$server"; do if [ "$p" -gt 0 ]; then kill "$p" 2>/dev/null || :; fi; done' EXIT
waitfor 'busctl --user status org.freedesktop.Notifications >/dev/null 2>&1'
/usr/bin/sparky-stereo-problems-notifier >"$D/notifier.log" 2>&1 & notifier=$!
# Read the actual notice and its Repair action before any package replacement.
waitfor 'python3 -c '\''import json; d=json.load(open("/opt/pe661-upgrade/notify.json"))["notify"]; assert any("Repair" in x["actions"] and "Before Upgrade" in x["body"] for x in d)'\'' 2>/dev/null'
old_hash=$(sha256sum /proc/$notifier/exe | cut -d' ' -f1)
echo "PASS  notification is open before upgrade; notifier PID $notifier, binary $old_hash"
touch "$D/ready"
waitfor '[ -f "$D/upgraded" ]'
kill -0 "$notifier"
new_hash=$(sha256sum /proc/$notifier/exe | cut -d' ' -f1)
[ "$new_hash" = "$old_hash" ]
echo "PASS  the same old notifier remains alive after both packages upgrade"
agent_dir=$(mktemp -d)
mkfifo "$agent_dir/ready"
pkttyagent --process "$notifier" --notify-fd 3 3>"$agent_dir/ready" & agent=$!
read -r _ <"$agent_dir/ready" || :
kill -0 "$agent"
nid=$(python3 -c 'import json; print(next(x["id"] for x in json.load(open("/opt/pe661-upgrade/notify.json"))["notify"] if "Repair" in x["actions"] and "Before Upgrade" in x["body"]))')
busctl --user call org.freedesktop.Notifications /test org.sparkylinux.Test Invoke us "$nid" Repair
waitfor '[ -f /run/pe661-upgrade-repaired ] && [ ! -e /var/lib/sparky-stereo-problems/sparky-stereo-problems_before-upgrade.json ]'
echo "PASS  Repair on the original notice runs the root-kept repair after upgrade"
printf 'PASS\n' >"$D/result"
kill "$agent" "$notifier" "$server" 2>/dev/null || :
wait "$agent" "$notifier" "$server" 2>/dev/null || :
rm -r "$agent_dir"
EOS
chmod 755 /opt/pe661-upgrade/person
# An isolated real login session supplies the terminal agent and private notification bus.
script -q -e -c 'systemd-run --quiet --wait --collect --pty --uid=person --property=PAMName=login dbus-run-session -- /opt/pe661-upgrade/person' /dev/null & session=$!
trap 'kill "$session" 2>/dev/null || :' EXIT
for i in $(seq 1 150); do [ -f /opt/pe661-upgrade/ready ] && break; sleep 0.2; done
[ -f /opt/pe661-upgrade/ready ]
dpkg -i "$NEW" "$NEW_PLASMA"
touch /opt/pe661-upgrade/upgraded
wait "$session"
grep -qx PASS /opt/pe661-upgrade/result
[ -f /run/pe661-upgrade-repaired ]
echo 'RESULT: original notification repaired after upgrade'
