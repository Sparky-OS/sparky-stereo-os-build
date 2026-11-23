#!/bin/bash
# ORDER 428: red and green runs of proof-checks.sh on planted logs, so the checks can be seen to fail.
# Run in a container:  docker run --rm --network none -v PROOF_SCRIPTS:/proof:ro IMAGE bash /proof/test-checks.sh
set -u
T=$(mktemp -d); O=$T/out; mkdir -p $O; PASSED=0
pass() { echo "PASS $*" >>$O/checks.txt; PASSED=$((PASSED+1)); }
fail() { echo "FAIL $*" >>$O/checks.txt; exit 1; }
. /proof/proof-checks.sh
bad=0
expect() { # expect red|green NAME COMMAND...   (the command runs in a subshell, because fail exits)
	local want=$1 name=$2; shift 2
	if ( "$@" ) >$T/last.txt 2>&1; then got=green; else got=red; fi
	if [ $got = $want ]; then echo "ok   $want  $name"; else echo "FAIL $name: wanted $want, got $got"; cat $T/last.txt; bad=1; fi
}
cat >$T/up-ok.txt <<'L'
Inst libfoo [1.0] (1.1 mashtabba:mashtabba [amd64])
Inst sparky-stereo-time [1] (2 mashtabba:mashtabba [all])
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
L
cat >$T/up-nothing.txt <<'L'
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
L
{ cat $T/up-ok.txt; echo "Remv hello [2.10-3]"; } >$T/up-remv.txt
{ echo "The following packages have been kept back:"; echo "  libfoo"; cat $T/up-ok.txt; } >$T/up-kept.txt
printf '# none\n' >$T/allow-none.txt; printf 'hello  replaced by hello-traditional\n' >$T/allow-hello.txt
expect green "Inst lines, nothing removed" check_inst_remv $T/up-ok.txt $T/allow-none.txt "t"
expect red   "no Inst line at all (proof of nothing)" check_inst_remv $T/up-nothing.txt $T/allow-none.txt "t"
expect red   "a Remv line not in the allowed list" check_inst_remv $T/up-remv.txt $T/allow-none.txt "t"
expect green "a Remv line the allowed list names" check_inst_remv $T/up-remv.txt $T/allow-hello.txt "t"
expect red   "a package kept back" check_inst_remv $T/up-kept.txt $T/allow-none.txt "t"
printf 'Unpacking libfoo (1.1) over (1.0) ...\nSetting up libfoo (1.1) ...\n' >$T/real-ok.txt
{ cat $T/real-ok.txt; echo 'Removing hello (2.10-3) ...'; } >$T/real-remv.txt
printf 'Setting up libfoo (1.1) ...\n' >$T/real-none.txt
expect green "real log: unpacked, nothing removed" check_real_log $T/real-ok.txt $T/allow-none.txt "t"
expect red   "real log: nothing unpacked" check_real_log $T/real-none.txt $T/allow-none.txt "t"
expect red   "real log: an unlisted removal" check_real_log $T/real-remv.txt $T/allow-none.txt "t"
expect green "real log: a listed removal" check_real_log $T/real-remv.txt $T/allow-hello.txt "t"
{ cat $T/real-ok.txt; echo "Removing 'diversion of /bin/example to /bin/example.usr-is-merged by example-bin'"; } >$T/real-divert.txt
{ cat $T/real-divert.txt; echo 'Removing hello:i386 (2.10-3) ...'; } >$T/real-divert-remv.txt
{ cat $T/real-ok.txt; echo 'Removing unexpected-output'; } >$T/real-unknown.txt
expect green "real log: diversion removal is not a package removal" check_real_log $T/real-divert.txt $T/allow-none.txt "t"
expect red   "real log: diversion plus unlisted multiarch removal" check_real_log $T/real-divert-remv.txt $T/allow-none.txt "t"
expect green "real log: diversion plus listed multiarch removal" check_real_log $T/real-divert-remv.txt $T/allow-hello.txt "t"
expect red   "real log: unknown Removing line still fails" check_real_log $T/real-unknown.txt $T/allow-none.txt "t"
echo 'Inst dpkg [1.23.11] (1.23.11+stereo3d2+lc1 mashtabba:mashtabba [amd64])' >$T/sim-ed.txt
echo 'Inst dpkg [1.23.11] (1.23.11 Debian:testing [amd64])' >$T/sim-deb.txt
expect green "simulation offers the edition's dpkg" check_sim_edition_dpkg $T/sim-ed.txt
expect red   "simulation offers Debian's dpkg" check_sim_edition_dpkg $T/sim-deb.txt
expect red   "simulation without any dpkg line" check_sim_edition_dpkg $T/up-ok.txt
printf 'a\nb\n' >$T/f1; printf 'a\n# planted by the upgrade proof (ORDER 428): a person'"'"'s edit\n' >$T/f2
printf '%s\t%s\t%s\n' $T/f2 x pkg >$T/pl-ok.tsv; printf '%s\t%s\t%s\n' $T/f1 x pkg >$T/pl-lost.tsv; : >$T/pl-empty.tsv
expect green "planted edit still there" check_planted_conffiles $T/pl-ok.tsv
expect red   "planted edit lost" check_planted_conffiles $T/pl-lost.tsv
expect red   "nothing was planted" check_planted_conffiles $T/pl-empty.tsv
printf '%s\t%s\t%s\n' /etc/x/planted.sh x pkg >$T/vp.tsv
printf 'LCCHANGED /etc/x/planted.sh (differs from its build-time payload; user edits remain untouched)\ndpkg-stereo: 10 projected files checked, 1 problems, 2 lc1 package manifests checked\n' >$T/v-planted.log
printf 'LCCHANGED /etc/x/other.sh (differs from its build-time payload; user edits remain untouched)\ndpkg-stereo: 10 projected files checked, 1 problems, 2 lc1 package manifests checked\n' >$T/v-other.log
printf 'MISSING /usr/lib/x.so\ndpkg-stereo: 10 projected files checked, 1 problems, 2 lc1 package manifests checked\n' >$T/v-missing.log
printf 'LCCHANGED /etc/x/planted.sh (differs from its build-time payload; user edits remain untouched)\ndpkg-stereo: 10 projected files checked, 2 problems, 2 lc1 package manifests checked\n' >$T/v-count.log
printf 'dpkg-stereo: 10 projected files checked, 0 problems, 2 lc1 package manifests checked\n' >$T/v-clean.log
printf 'LCCHANGED /etc/x/planted.sh (differs from its build-time payload; user edits remain untouched)\nAFTERINST /etc/issue (changed after the install; dpkg-stereo did not project it, and leaves it)\ndpkg-stereo: 10 projected files checked, 1 problems, 2 lc1 package manifests checked, 1 files dpkg-stereo did not project, changed after the install (AFTERINST, information, not counted)\n' >$T/v-deep.log
expect green "verify --deep: a planted edit and an AFTERINST line" check_verify v $T/v-deep.log 1 $T/vp.tsv
expect green "verify clean" check_verify v $T/v-clean.log 0 $T/vp.tsv
expect green "verify: only a planted person edit" check_verify v $T/v-planted.log 1 $T/vp.tsv
expect red   "verify: a changed file nobody planted" check_verify v $T/v-other.log 1 $T/vp.tsv
expect red   "verify: another kind of problem" check_verify v $T/v-missing.log 1 $T/vp.tsv
expect red   "verify: the count does not match the lines" check_verify v $T/v-count.log 1 $T/vp.tsv
expect red   "verify: an incomplete check (rc 2)" check_verify v $T/v-planted.log 2 $T/vp.tsv
rm -rf $T
[ $bad = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
