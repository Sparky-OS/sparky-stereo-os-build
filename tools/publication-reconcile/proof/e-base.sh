#!/bin/bash
# proof (e), phase 1 (ORDER 428): a system on the EDITION'S OWN dpkg. The live set's dpkg and dpkg-stereo are installed first,
# from the live repository (/base) with its pins; apt's Inst line must offer the edition's dpkg (+stereo), `dpkg --version`
# and `dpkg-query -W dpkg` are recorded; then the packages E_PACKAGES are installed with that dpkg doing the work (a
# stock-dpkg proof can pass where the edition's dpkg refuses, ORDER 413).
# Environment: E_PACKAGES (default: the user meta and both developer tasks), E_I386 (default 1: add the i386 architecture).
. /proof/proof-common.sh
. /proof/proof-checks.sh
set +e
trap 'chown -R 1000:1000 /out' EXIT
set -u
: "${E_PACKAGES:=sparky-stereo task-sparky-stereo-developer task-sparky-stereo-os-developer}"
[ "${E_I386:-1}" = 1 ] && dpkg --add-architecture i386
echo "stock dpkg before: $(dpkg --version | head -1); $(dpkg-query -W dpkg)" | tee -a $O/rc.txt
setup_sources; edition /base
update_all $O/e1-update.log; echo "update rc=$?" | tee -a $O/rc.txt
apt_get -s -y install dpkg dpkg-stereo >$O/e1-sim-dpkg.txt 2>&1; echo "sim dpkg rc=$?" | tee -a $O/rc.txt
grep -E '^(Inst|Remv) ' $O/e1-sim-dpkg.txt | tee -a $O/rc.txt
check_sim_edition_dpkg $O/e1-sim-dpkg.txt
apt_get -y -q install dpkg dpkg-stereo >$O/e1-dpkg.log 2>&1; rc=$?; echo "install dpkg dpkg-stereo rc=$rc" | tee -a $O/rc.txt
[ $rc = 0 ] || fail "installing the edition's dpkg failed (rc=$rc): $(grep -E '^(E:|dpkg: error)' $O/e1-dpkg.log | head -3)"
check_edition_dpkg "base, after installing dpkg from the live set"
apt_get -y -q install --no-install-recommends gcc >$O/e1-gcc.log 2>&1; echo "gcc first rc=$?" | tee -a $O/rc.txt
apt_get -y -q install --no-install-recommends $E_PACKAGES >$O/e1-install.log 2>&1; rc=$?
echo "base install rc=$rc ($E_PACKAGES)" | tee -a $O/rc.txt
echo "base Inst lines: $(grep -c '^Inst' $O/e1-install.log), Remv: $(grep -c '^Remv' $O/e1-install.log)" | tee -a $O/rc.txt
[ $rc = 0 ] || fail "base install failed (rc=$rc): $(grep -E '^(E:|dpkg: error)' $O/e1-install.log | head -3)"
check_edition_dpkg "base, after installing the package set"
snapshot $O/e1-snapshot.txt
dpkg --audit >$O/e1-audit.txt 2>&1; [ ! -s $O/e1-audit.txt ] && pass "base: dpkg --audit is empty" || fail "base: dpkg --audit says: $(head -3 $O/e1-audit.txt)"
apt_get clean
exit 0
