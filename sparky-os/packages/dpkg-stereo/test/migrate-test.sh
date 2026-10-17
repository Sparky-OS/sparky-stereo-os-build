#!/bin/sh
# An older dpkg-stereo (0.1.2 with one files.tsv, or 0.1.3 with records per package) upgraded to this one
# in a Debian container: the records move over at the first dpkg run, the upgrade projects nothing again
# (only its own post-invoke run reads what changed), verify stays clean, a reinstall stays quiet; then
# the way back and a new install, which projects everything again.
# Usage: migrate-test.sh OLD.deb NEW.deb
set -u
OLD=$1 NEW=$2
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
count() { if [ -f /var/lib/dpkg-stereo/files.tsv ]; then grep -vc '^#' /var/lib/dpkg-stereo/files.tsv; else cat /var/lib/dpkg-stereo/records/*.tsv | grep -vc '^#'; fi; }
dpkg --verify > /tmp/dv0.log 2>&1
dpkg -i "$OLD" < /dev/null > /tmp/old.log 2>&1 || bad "install $(basename "$OLD")"
n_old=$(count)
[ "$n_old" -gt 0 ] && ok "$(basename "$OLD") projected at its first install ($n_old records)" || bad "no records after the first install"
t0=$(date +%s%N); dpkg -i "$NEW" < /dev/null > /tmp/new.log 2>&1 || bad "upgrade: $(tail -3 /tmp/new.log)"; t1=$(date +%s%N)
grep -q 'examined' /tmp/new.log && bad "the upgrade projected every package again: $(grep examined /tmp/new.log)" || ok "the upgrade projected nothing again ($(( (t1 - t0) / 1000000 )) ms)"
[ ! -f /var/lib/dpkg-stereo/files.tsv ] && [ -d /var/lib/dpkg-stereo/records ] && ok "records per package ($(ls /var/lib/dpkg-stereo/records | wc -l) packages)" || bad "records not moved"
n_new=$(count)
[ "$n_new" -ge $((n_old - 20)) ] && ok "records kept: $n_old before, $n_new after" || bad "records lost: $n_old before, $n_new after"
dpkg-stereo --verify > /tmp/verify.log 2>&1 && ok "verify: $(tail -1 /tmp/verify.log)" || bad "verify: $(tail -3 /tmp/verify.log)"
t0=$(date +%s%N); apt-get install -y --reinstall -o Dpkg::Use-Pty=0 bash-completion > /tmp/re.log 2>&1 || dpkg -i /var/cache/apt/archives/bash-completion_*.deb > /tmp/re.log 2>&1; t1=$(date +%s%N)
dpkg-stereo --verify > /tmp/verify2.log 2>&1 && ok "after a reinstall ($(( (t1 - t0) / 1000000 )) ms): $(tail -1 /tmp/verify2.log)" || bad "verify after reinstall: $(tail -3 /tmp/verify2.log)"
echo "== the way back, then a new install"
t0=$(date +%s%N); dpkg -r dpkg-stereo < /dev/null > /tmp/rm.log 2>&1 || bad "remove: $(tail -3 /tmp/rm.log)"; t1=$(date +%s%N)
# a file stays lean only when its package's .deb at the installed version is neither in APT's cache nor in
# the archive (the archive moved on): those packages must be named, and be the only ones left
cat /var/lib/dpkg-stereo/records/*.tsv 2>/dev/null | grep -v '^#' | cut -f1 | sort > /tmp/remain.paths
cat /var/lib/dpkg-stereo/records/*.tsv 2>/dev/null | grep -v '^#' | cut -f2,3 | sort -u > /tmp/remain.pkgs
reach=
mkdir -p /tmp/dl
while IFS="$(printf '\t')" read -r p v; do
	(cd /tmp/dl && apt-get download "${p%%:*}=$v" > /dev/null 2>&1) && reach="$reach $p=$v"
	grep -q "^dpkg-stereo: $p $v: .* files stay lean" /tmp/rm.log || reach="$reach (not named: $p)"
done < /tmp/remain.pkgs
[ -z "$reach" ] && ok "removed in $(( (t1 - t0) / 1000000 )) ms: $(grep 'files restored' /tmp/rm.log); left lean only where the archive moved on: $(cut -f1 /tmp/remain.pkgs | tr '\n' ' ')" || bad "after removal: records of reachable packages remain:$reach"
dpkg --verify > /tmp/dv1.log 2>&1
diff /tmp/dv0.log /tmp/dv1.log | sed -n 's/^> ..5.......* //p' | sort > /tmp/dv.paths
cmp -s /tmp/dv.paths /tmp/remain.paths && ok "dpkg --verify: as before dpkg-stereo, but for the $(grep -c . /tmp/remain.paths) files that stay lean" || bad "dpkg --verify after removal: $(diff /tmp/dv.paths /tmp/remain.paths | head -5)"
dpkg -i "$NEW" < /dev/null > /tmp/again.log 2>&1 || bad "install again: $(tail -3 /tmp/again.log)"
grep -q 'examined' /tmp/again.log && ok "a new install after the removal projects again: $(grep examined /tmp/again.log)" || bad "a new install did not project"
n_again=$(count)
[ "$n_again" -ge $((n_old - 20)) ] && ok "records again: $n_again" || bad "records after the new install: $n_again (first install $n_old)"
dpkg-stereo --verify > /tmp/verify3.log 2>&1 && ok "verify: $(tail -1 /tmp/verify3.log)" || bad "verify after the new install: $(tail -3 /tmp/verify3.log)"
[ ! -s /var/lib/dpkg-stereo/error.log ] && ok "no hook errors" || bad "hook errors: $(tail -5 /var/lib/dpkg-stereo/error.log)"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
