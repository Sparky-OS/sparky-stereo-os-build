# sourced inside pj18-inst:1 as root: makes user tester, then `as_tester SCRIPT` runs a script as uid 1000
useradd -m -u 1000 tester 2>/dev/null || true
chown 1000:1000 /scratch 2>/dev/null || true
as_tester() { su tester -c "env STEPS=\"${STEPS:-pdf login}\" HOME=/home/tester LANG=C.UTF-8 LC_ALL=C.UTF-8 DISPLAY=:99 XDG_STATE_HOME=/home/tester/.local/state bash $1"; }
