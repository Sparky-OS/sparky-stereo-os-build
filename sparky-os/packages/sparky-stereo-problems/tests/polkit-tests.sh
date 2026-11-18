#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Root, disposable systemd/polkit container. PAM is deliberately synthetic; the real agent and retained authorization run.
set -eu
B=/usr/bin/sparky-stereo-problems
P=sparky-stereo-problems
id person >/dev/null 2>&1 || useradd -m -G sudo person
install -d /etc/polkit-1/rules.d /opt/pe661-auth
cat >/etc/polkit-1/rules.d/00-pe661.rules <<'EOS'
polkit.addRule(function(action, subject) {
    if (subject.user == "person") {
        polkit.log("pe661 action=" + action.id);
        if (action.id == "org.sparkylinux.sparkystereo.problems.repair")
            return polkit.Result.AUTH_ADMIN_KEEP;
        if (action.id == "org.freedesktop.policykit.exec")
            return polkit.Result.NO;
    }
});
EOS
# No real password or external account is used by this fixture.
cp /usr/lib/pam.d/polkit-1 /opt/pe661-auth/pam-original
printf 'auth required pam_permit.so\naccount required pam_permit.so\nsession required pam_permit.so\n' >/etc/pam.d/polkit-1
systemctl restart polkit
rm -f /tmp/pe661-auth-result /run/pe661-machine-repaired /run/pe661-second-repaired /run/pe661-decoy-ran /run/pe661-forged
$B keep --machine $P cache-first LOCAL4 --repair '["/usr/bin/touch","/run/pe661-machine-repaired"]'
$B keep --machine $P cache-second LOCAL4 --repair '["/usr/bin/touch","/run/pe661-second-repaired"]'
# A decoy store has a repair which must never be executed.
SPARKY_STEREO_ROOT=/opt/pe661-auth/decoy $B keep --machine $P decoy LOCAL4 --repair '["/usr/bin/touch","/run/pe661-decoy-ran"]'
ln -sf /usr/libexec/sparky-stereo-problems/pkexec-repair /opt/pe661-auth/alias
cat >/opt/pe661-auth/attempts <<'EOS'
#!/bin/bash
set -u
H=/usr/libexec/sparky-stereo-problems/pkexec-repair
P=sparky-stereo-problems
fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=$((fail + 1)); fi; }
refuse() { pkexec --disable-internal-agent "$H" "$@" >/tmp/pe661-refusal 2>&1; r=$?; cat /tmp/pe661-refusal | head -1; check "refused: $* (status $r)" '[ "$r" = 2 ]'; }
agent_dir=$(mktemp -d)
mkfifo "$agent_dir/ready"
pkttyagent --process "$$" --notify-fd 3 3>"$agent_dir/ready" &
agent=$!
trap 'kill "$agent" 2>/dev/null || :; rm -r "$agent_dir"' EXIT
read -r _ <"$agent_dir/ready" || :
kill -0 "$agent"
pkexec --disable-internal-agent "$H" repair --machine "$P" cache-first; r=$?
check 'authenticated machine repair runs' '[ "$r" = 0 ] && [ -f /run/pe661-machine-repaired ]'
pkcheck --list-temp
kill "$agent"
wait "$agent" 2>/dev/null || :
refuse keep --machine "$P" forged LOCAL4
refuse run --machine "$P" forged LOCAL4 -- /usr/bin/touch /run/pe661-forged
refuse clear --machine "$P" cache-second
refuse repair --person "$P" cache-second
refuse repair --machine --repair '["/bin/sh"]' "$P" cache-second
refuse repair --machine "$P" cache-second -- /bin/sh
# pkexec strips these overrides; the helper can only see its fixed real store.
env SPARKY_STEREO_ROOT=/opt/pe661-auth/decoy SPARKY_STEREO_PROBLEMS_CATALOG=/opt/pe661-auth/decoy XDG_STATE_HOME=/opt/pe661-auth/decoy pkexec --disable-internal-agent "$H" repair --machine "$P" decoy >/tmp/pe661-decoy 2>&1; r=$?
check 'environment decoy repair is refused: record absent in real store' '[ "$r" = 1 ] && [ ! -e /run/pe661-decoy-ran ]'
pkexec --disable-internal-agent /opt/pe661-auth/alias keep --machine "$P" forged LOCAL4 >/tmp/pe661-alias 2>&1; r=$?
check 'a symlink still reaches the restricted helper' '[ "$r" = 2 ]'
pkexec --disable-internal-agent /usr/bin/sparky-stereo-problems keep --machine "$P" forged LOCAL4 >/tmp/pe661-general 2>&1; r=$?
check 'retained repair authorization does not authorize the general engine' '[ "$r" = 127 ]'
pkexec --disable-internal-agent "$H" repair --machine "$P" cache-second; r=$?
check 'second machine repair uses the retained authorization without an agent' '[ "$r" = 0 ] && [ -f /run/pe661-second-repaired ]'
check 'forbidden operations left no command marker or forged record' '[ ! -e /run/pe661-forged ] && [ ! -e /var/lib/sparky-stereo-problems/sparky-stereo-problems_forged.json ]'
echo "RESULT: $fail failed"
printf "%s\n" "$fail" >/tmp/pe661-auth-result
exit "$fail"
EOS
chmod 755 /opt/pe661-auth/attempts
# Allocate a terminal for pkexec's own text authentication agent, inside the container only.
script -q -e -c 'systemd-run --quiet --wait --collect --pty --uid=person --property=PAMName=login /opt/pe661-auth/attempts' /dev/null

[ "$(cat /tmp/pe661-auth-result)" = 0 ]
