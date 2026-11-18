#!/bin/bash
# proof (e), phase 2 (ORDER 428): the same system, on the edition's dpkg, upgraded to the round's tree (/cand) with
# apt-get dist-upgrade, reading apt's Inst and Remv lines: a removal that is not in E_ALLOWED_REMV (a file in the proof folder,
# one package name per line, default none), a package kept back, an upgrade that installs nothing, a person's planted
# conffile edit that is lost, or a dpkg that is no longer the edition's, is a FAIL (exit 1 and verdict.txt).
. /proof/proof-common.sh
. /proof/proof-checks.sh
set +e
trap 'chown -R 1000:1000 /out' EXIT
set -u
ALLOW=/proof/${E_ALLOWED_REMV:-e-allowed-remv.txt}
check_edition_dpkg "before the upgrade"
edition /cand
update_all $O/e2-update.log; echo "cand update rc=$?" | tee -a $O/rc.txt
grep -E "^(Err|W:|E:)" $O/e2-update.log | head -5
snapshot $O/e2-before.txt
apt_get -s dist-upgrade >$O/e2-sim-dist.txt 2>&1; rc=$?; echo "sim dist-upgrade rc=$rc" | tee -a $O/rc.txt
[ $rc = 0 ] || fail "dist-upgrade simulation failed (rc=$rc)"
echo "dist-upgrade would: $(grep -c '^Inst' $O/e2-sim-dist.txt) Inst, $(grep -c '^Remv' $O/e2-sim-dist.txt) Remv; $(grep -E 'upgraded,' $O/e2-sim-dist.txt)" | tee -a $O/rc.txt
grep -E '^(Inst|Remv) ' $O/e2-sim-dist.txt | head -60
check_inst_remv $O/e2-sim-dist.txt "$ALLOW" "simulated dist-upgrade"
if [ -n "${E_TARGETS:-}" ]; then
    python3 /proof/check-upgrade-targets.py $O/e2-before.txt $O/e2-sim-dist.txt "$E_TARGETS" >$O/e2-targets.txt 2>&1 || fail "installed selected targets are missing from the simulation: $(head -3 $O/e2-targets.txt)"
    pass "every installed selected target is offered at its frozen version"
fi
# the packages the upgrade touches, for the planted conffile edits (only upgrades: Inst NAME [old] (new ...))
awk '/^Inst .*\[/{print $2}' $O/e2-sim-dist.txt | sed 's/:[a-z0-9]*$//' | sort -u >$O/e2-upgraded.txt
plant_conffiles $O/e2-planted.tsv $O/e2-upgraded.txt
echo "planted conffile edits: $(wc -l <$O/e2-planted.tsv)" | tee -a $O/rc.txt
apt_get -y -q dist-upgrade >$O/e2-dist-upgrade.log 2>&1; rc=$?
echo "REAL dist-upgrade rc=$rc" | tee -a $O/rc.txt
echo "real Inst $(grep -c '^Inst' $O/e2-dist-upgrade.log), Remv $(grep -c '^Remv' $O/e2-dist-upgrade.log), $(grep -E 'upgraded,' $O/e2-dist-upgrade.log)" | tee -a $O/rc.txt
[ $rc = 0 ] || fail "the real dist-upgrade failed (rc=$rc): $(grep -E '^(E:|dpkg: error)' $O/e2-dist-upgrade.log | head -3)"
check_real_log $O/e2-dist-upgrade.log "$ALLOW" "real dist-upgrade"
snapshot $O/e2-after.txt; compare $O/e2-before.txt $O/e2-after.txt $O/e2-cmp | tee -a $O/rc.txt
check_edition_dpkg "after the upgrade"
check_planted_conffiles $O/e2-planted.tsv
apt_get -s dist-upgrade >$O/e2-sim-again.txt 2>&1 || fail "second upgrade simulation failed"
[ "$(grep -c '^Inst' $O/e2-sim-again.txt)" = 0 ] && [ "$(grep -c '^Remv' $O/e2-sim-again.txt)" = 0 ] && pass "second pass: nothing left to do" || fail "second pass would still change: $(grep -E '^(Inst|Remv)' $O/e2-sim-again.txt | head -3)"
dpkg --audit >$O/e2-audit.txt 2>&1; [ ! -s $O/e2-audit.txt ] && pass "dpkg --audit is empty" || fail "dpkg --audit: $(head -3 $O/e2-audit.txt)"
dpkg-stereo --verify >$O/e2-verify.log 2>&1; vrc=$?; echo "dpkg-stereo --verify rc=$vrc : $(tail -1 $O/e2-verify.log)" | tee -a $O/rc.txt
check_verify "dpkg-stereo --verify" $O/e2-verify.log $vrc $O/e2-planted.tsv
dpkg-stereo --verify --deep >$O/e2-verify-deep.log 2>&1; vrc=$?; echo "dpkg-stereo --verify --deep rc=$vrc : $(tail -1 $O/e2-verify-deep.log)" | tee -a $O/rc.txt
check_verify "dpkg-stereo --verify --deep" $O/e2-verify-deep.log $vrc $O/e2-planted.tsv
echo "PASS ($PASSED checks)" | tee $O/verdict.txt
exit 0
