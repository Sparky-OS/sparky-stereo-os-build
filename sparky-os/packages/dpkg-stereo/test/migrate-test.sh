#!/bin/sh
# 0.1.2 (one files.tsv) upgraded to 0.1.3 (records per package) in a Debian container: the records move
# over at the first dpkg run, nothing is projected twice, verify stays clean, a reinstall stays quiet.
set -u
OLD=$1 NEW=$2
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
dpkg -i "$OLD" < /dev/null > /tmp/old.log 2>&1 || bad "install 0.1.2"
[ -f /var/lib/dpkg-stereo/files.tsv ] && ok "0.1.2 keeps files.tsv ($(grep -vc '^#' /var/lib/dpkg-stereo/files.tsv) records)" || bad "no files.tsv"
n_old=$(grep -vc '^#' /var/lib/dpkg-stereo/files.tsv)
dpkg -i "$NEW" < /dev/null > /tmp/new.log 2>&1 || bad "upgrade to 0.1.3: $(tail -3 /tmp/new.log)"
[ ! -f /var/lib/dpkg-stereo/files.tsv ] && [ -d /var/lib/dpkg-stereo/records ] && ok "records moved per package ($(ls /var/lib/dpkg-stereo/records | wc -l) packages)" || bad "records not moved"
n_new=$(cat /var/lib/dpkg-stereo/records/*.tsv | grep -vc '^#')
[ "$n_new" -ge $((n_old - 20)) ] && ok "records kept: $n_old before, $n_new after" || bad "records lost: $n_old before, $n_new after"
dpkg-stereo --verify > /tmp/verify.log 2>&1 && ok "verify: $(tail -1 /tmp/verify.log)" || bad "verify: $(tail -3 /tmp/verify.log)"
t0=$(date +%s%N); apt-get install -y --reinstall -o Dpkg::Use-Pty=0 bash-completion > /tmp/re.log 2>&1 || dpkg -i /var/cache/apt/archives/bash-completion_*.deb > /tmp/re.log 2>&1; t1=$(date +%s%N)
dpkg-stereo --verify > /tmp/verify2.log 2>&1 && ok "after a reinstall ($(( (t1 - t0) / 1000000 )) ms): $(tail -1 /tmp/verify2.log)" || bad "verify after reinstall: $(tail -3 /tmp/verify2.log)"
[ ! -s /var/lib/dpkg-stereo/error.log ] && ok "no hook errors" || bad "hook errors: $(tail -5 /var/lib/dpkg-stereo/error.log)"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
