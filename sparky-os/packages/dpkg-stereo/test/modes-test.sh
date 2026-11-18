#!/bin/sh
# ORDER 707: the verifier's trust check meets a folder an early dpkg-stereo left group-writable.
# Usage: modes-test.sh DPKG-STEREO.deb WORKDIR   (a throwaway ds707- container, root, no network, the published
# edition installed: dpkg 1.23.11+stereo3d3+lc1 and a dpkg-stereo; DEB is the one under test)
# Red on 0.1.41 (reinstalling it leaves the folders as they are, the refusal does not name the folder, repair cannot
# settle), green on its successor. Every scenario ends with its packages purged.
set -u
DEB=$1 W=$2
export DEBIAN_FRONTEND=noninteractive
. "$(dirname "$0")/modes-lib.sh"
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
check() { # check DESCRIPTION COMMAND...
	d=$1; shift
	if "$@"; then ok "$d"; else bad "$d"; fi
}
mkdir -p "$W"
TREE=/usr/lib/dpkg-stereo
shaof() { sha256sum "$@" | cut -d' ' -f1 | tr '\n' ' '; }
files_of() { echo /etc/default/$1 /etc/init.d/$1 /etc/X11/Xsession.d/20$1; }
projected_new() { # every conffile of $1 is lean and carries the new value
	for f in $(files_of $1); do grep -q 'Lean Code' $f && grep -q 'new$' $f || return 1; done
}
no_dist() { for f in $(files_of $1); do [ -e $f.dpkg-dist ] || [ -e $f.dpkg-new ] && return 1; done; return 0; }
says() { dpkg-stereo --problems 2>&1 | grep -q -- "$1"; }
install_fx() { mk_pkg $1 1.0 old; mk_pkg $1 2.0 new; dpkg -i $W/$1_1.0_all.deb </dev/null >$W/$1-1.log 2>&1 || bad "$1 1.0 install: $(tail -2 $W/$1-1.log)"; }
upgrade_fx() { dpkg "$@" -i $W/$FX\_2.0_all.deb </dev/null >$W/$FX-2.log 2>&1; }
problems() { dpkg-stereo --problems 2>&1; }
no_problem() { dpkg-stereo --problems >/dev/null 2>&1; }
group_writable() { chmod g+w $TREE $TREE/lean; }
mode_of() { stat -c %a "$1"; }
done_fx() { dpkg -P $1 </dev/null >/dev/null 2>&1; }
nothing_named() { ! dpkg-stereo --repair 2>&1 | grep -q '/usr/lib '; }
settle_state() { chmod 755 $TREE $TREE/lean /usr/lib; dpkg-stereo --repair >/dev/null 2>&1; }

echo "== the package under test ships its folders 0755, root-owned"
bad_dirs=$(dpkg-deb -c "$DEB" | awk '$1 ~ /^d/ && ($1 != "drwxr-xr-x" || $2 != "root/root")' | wc -l)
check "no folder of the package is other than drwxr-xr-x root/root ($bad_dirs)" [ "$bad_dirs" = 0 ]

echo "== install the package under test (a reinstall for 0.1.41, an upgrade for its successor)"
DPKG_STEREO_NO_PROJECT=1 dpkg -i "$DEB" </dev/null >"$W/successor.log" 2>&1 || bad "install of the package under test: $(tail -3 $W/successor.log)"
dpkg-stereo --repair >/dev/null 2>&1

echo "== S0 control: folders at 0755, an upgrade that changes three projected conffiles completes"
FX=fxa; install_fx $FX; upgrade_fx --force-confnew
check "S0 no conffile problem kept" no_problem
check "S0 all three conffiles are the new version, projected" projected_new $FX
check "S0 no .dpkg-dist or .dpkg-new left" no_dist $FX
done_fx $FX

echo "== S1 the measured state: an early package left the folders group-writable; the successor is installed, then the upgrade"
FX=fxb; install_fx $FX
group_writable
DPKG_STEREO_NO_PROJECT=1 dpkg -i "$DEB" </dev/null >"$W/successor2.log" 2>&1
check "S1 the folders are 0755 once the package is configured ($(mode_of $TREE) $(mode_of $TREE/lean))" [ "$(mode_of $TREE)$(mode_of $TREE/lean)" = 755755 ]
upgrade_fx --force-confnew
check "S1 no conffile problem kept" no_problem
check "S1 all three conffiles are the new version, projected" projected_new $FX
done_fx $FX

echo "== S2 the real order: the upgrade runs first and is refused, then the successor, then repair"
FX=fxc; install_fx $FX
group_writable
upgrade_fx --force-confnew
check "S2 the refusal is kept (the red state: three entries)" says '3 conffiles used dpkg conflict handling'
before=$(shaof $(files_of $FX))
DPKG_STEREO_NO_PROJECT=1 dpkg -i "$DEB" </dev/null >"$W/successor3.log" 2>&1
dpkg-stereo --repair >"$W/s2-repair.log" 2>&1; rc=$?
check "S2 repair exits 0 ($rc)" [ "$rc" = 0 ]
check "S2 the problem is cleared" no_problem
check "S2 no conffile byte changed by repair" [ "$before" = "$(shaof $(files_of $FX))" ]
done_fx $FX

echo "== S3 the check is not weakened: a folder made group-writable after the fix is refused, named, and repair mends it"
FX=fxd; install_fx $FX
group_writable
upgrade_fx --force-confnew
check "S3 the refusal is kept" says 'conffiles used dpkg conflict handling'
check "S3 it names the folder and its mode" says "$TREE.*775"
before=$(shaof $(files_of $FX))
dpkg-stereo --repair >"$W/s3-repair.log" 2>&1; rc=$?
check "S3 repair exits 0 ($rc)" [ "$rc" = 0 ]
check "S3 repair says what it set ($(grep -c "$TREE" $W/s3-repair.log) lines name the folder)" grep -q "$TREE" "$W/s3-repair.log"
check "S3 the folders are 0755 again" [ "$(mode_of $TREE)$(mode_of $TREE/lean)" = 755755 ]
check "S3 the problem is cleared" no_problem
check "S3 no conffile byte changed" [ "$before" = "$(shaof $(files_of $FX))" ]
done_fx $FX

echo "== S4 a conffile the person edited stays the person's through the whole path"
FX=fxe; install_fx $FX
echo "OPTION=mine" >>/etc/default/$FX
edited=$(shaof /etc/default/$FX)
group_writable
upgrade_fx --force-confold
DPKG_STEREO_NO_PROJECT=1 dpkg -i "$DEB" </dev/null >/dev/null 2>&1
dpkg-stereo --repair >"$W/s4-repair.log" 2>&1; rc=$?
check "S4 the edited file is byte for byte the person's" [ "$edited" = "$(shaof /etc/default/$FX)" ]
check "S4 the package's version waits beside it as .dpkg-dist" [ -e /etc/default/$FX.dpkg-dist ]
check "S4 repair does not call the choice settled (exit $rc)" says "/etc/default/$FX"
done_fx $FX
settle_state

echo "== S5 its own tree only: a group-writable /usr/lib is named and left to its owner"
FX=fxf; install_fx $FX
chmod g+w /usr/lib
upgrade_fx --force-confnew
check "S5 the refusal names /usr/lib" says '/usr/lib .*775'
dpkg-stereo --repair >"$W/s5-repair.log" 2>&1; rc=$?
check "S5 repair left /usr/lib alone ($(mode_of /usr/lib))" [ "$(mode_of /usr/lib)" = 775 ]
check "S5 repair still names /usr/lib, which it cannot mend (exit $rc)" grep -q '/usr/lib .*775' "$W/s5-repair.log"
chmod 755 /usr/lib
check "S5 once its owner fixes it, nothing is named" nothing_named
done_fx $FX

echo "== S6 one dpkg run: the successor first, a package with projected conffiles after it"
FX=fxg; install_fx $FX
group_writable
dpkg --force-confnew -i "$DEB" $W/${FX}_2.0_all.deb </dev/null >"$W/s6.log" 2>&1
check "S6 no conffile problem kept" no_problem
check "S6 all three conffiles are the new version, projected" projected_new $FX
done_fx $FX
exit $fail
