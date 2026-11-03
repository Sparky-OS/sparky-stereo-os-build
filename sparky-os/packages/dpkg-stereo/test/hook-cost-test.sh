#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# A dpkg run that changes nothing costs dpkg-stereo's hooks no rewrite and no read of a package's files (ORDER 367),
# and every rule of the runs that do change something stays, in a throwaway Debian container (root) with the edition's
# dpkg and dpkg-stereo installed:
#   A. `dpkg --configure -a` with nothing to configure: no projected conffile is written again (0.1.28 put every lean
#      conffile back in its package's bytes before the run and projected it again after), packages.tsv and the records
#      stay byte for byte, --verify stays clean
#   B. a conffile the person put back in its package's bytes is projected again by the next such run; a conffile the
#      person edited stays as they made it, and --verify names it
#   C. a reinstall of the same version, in the second after a run and in a later one: its files projected again
#   D. an upgrade unpacked in one run and configured in the next: no conffile prompt, the new conffile arrives, lean
#   E. a package left unpacked with its records (its unpack ran with the hooks off, as a run stopped before its
#      post-invoke leaves it): the configure run gives dpkg the conffile's own bytes, so dpkg takes the new conffile
#      without asking, and projects it after
#   F. a removal and a purge: nothing of the package stays recorded or left, no conffile prompt
#   G. a hook that fails keeps its problem in the edition's engine, and the next run that succeeds clears it (the engine
#      is loaded only when the step has a record to clear)
# Usage: hook-cost-test.sh WORKDIR
set -u
W=$1
export DEBIAN_FRONTEND=noninteractive
fail=0 passed=0 failed=0
ok() { echo "PASS $*"; passed=$((passed + 1)); }
bad() { echo "FAIL $*"; fail=1; failed=$((failed + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
lean() { ! grep -q 'commentary' "$1"; }
stamp() { stat -c '%i %Z %Y %s' "$@"; }
state() { (cd /var/lib/dpkg-stereo && cat packages.tsv conffiles.tsv records/*.tsv left/*.tsv 2>/dev/null | sha256sum); }
settle() { sleep 2; dpkg --configure -a </dev/null >/dev/null 2>&1; }
mk() {   # mk NAME VERSION
	d=$W/src/$1-$2
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/xdg" "$d/etc/sysctl.d" "$d/usr/bin"
	printf '# %s defaults: commentary for people; KConfig reads groups and keys only.\n# A second line of commentary.\n[General]\nMode=%s\n' "$1" "$2" >"$d/etc/xdg/$1rc"
	printf '# %s: a kernel setting with commentary for people.\n# The kernel reads only the line below.\nvm.swappiness = 10\n' "$1" >"$d/etc/sysctl.d/90-$1.conf"
	printf '#!/bin/sh\n# %s %s: commentary the shell skips at every start.\n# A second line of commentary.\necho "%s %s"\n' "$1" "$2" "$1" "$2" >"$d/usr/bin/$1"
	chmod 755 "$d/usr/bin/$1"
	printf '/etc/xdg/%src\n/etc/sysctl.d/90-%s.conf\n' "$1" "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: hook cost test\n' "$1" "$2" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/$1_$2_all.deb" >/dev/null
}
command -v dpkg-stereo >/dev/null || { echo "dpkg-stereo is not installed: install it (and the edition's dpkg) first"; exit 2; }
rm -rf "$W"
mkdir -p "$W"
mk hc-a 1.0
mk hc-a 1.1
mk hc-b 1.0
dpkg -i "$W/hc-a_1.0_all.deb" "$W/hc-b_1.0_all.deb" </dev/null >"$W/install.log" 2>&1 || bad "install hc-a and hc-b: $(tail -3 "$W/install.log")"
check "control: hc-a's conffiles and script projected" bash -c "$(declare -f lean); lean /etc/xdg/hc-arc && lean /etc/sysctl.d/90-hc-a.conf && lean /usr/bin/hc-a"
CONF="/etc/xdg/hc-arc /etc/sysctl.d/90-hc-a.conf /etc/xdg/hc-brc /etc/sysctl.d/90-hc-b.conf"

echo "== A. dpkg --configure -a with nothing to configure"
settle
before=$(stamp $CONF) st=$(state)
dpkg --configure -a </dev/null >"$W/a.log" 2>&1 || bad "A: dpkg --configure -a: $(tail -3 "$W/a.log")"
check "A: no projected conffile written again" [ "$(stamp $CONF)" = "$before" ]
check "A: packages.tsv and the records as they were" [ "$(state)" = "$st" ]
dpkg --configure -a </dev/null >"$W/a2.log" 2>&1
check "A: a second run the same" [ "$(stamp $CONF)" = "$before" ]
dpkg-stereo --verify hc-a hc-b >"$W/verify-a.log" 2>&1
check "A: verify clean" grep -q ' 0 problems' "$W/verify-a.log"

echo "== B. the person's own bytes back in a conffile, and the person's edit"
dpkg-deb --fsys-tarfile "$W/hc-a_1.0_all.deb" | tar -xO ./etc/xdg/hc-arc >/etc/xdg/hc-arc
printf 'Edited=by the person\n' >>/etc/xdg/hc-brc
cp /etc/xdg/hc-brc "$W/edited"
check "B: control: hc-arc in its package's bytes" grep -q commentary /etc/xdg/hc-arc
dpkg --configure -a </dev/null >"$W/b.log" 2>&1 || bad "B: dpkg --configure -a: $(tail -3 "$W/b.log")"
check "B: the next run projected hc-arc again" lean /etc/xdg/hc-arc
check "B: the person's edit stays" cmp -s /etc/xdg/hc-brc "$W/edited"
dpkg-stereo --verify hc-a hc-b >"$W/verify-b.log" 2>&1
check "B: verify names the edit once, as the person's" sh -c "[ \"\$(grep -c 'hc-brc' '$W/verify-b.log')\" = 1 ] && grep -qx 'CHANGED   /etc/xdg/hc-brc (changed by the person)' '$W/verify-b.log'"

echo "== C. a reinstall of the same version"
settle
dpkg -i "$W/hc-a_1.0_all.deb" </dev/null >"$W/c1.log" 2>&1 || bad "C: reinstall: $(tail -3 "$W/c1.log")"
check "C: right after a run: projected again" bash -c "$(declare -f lean); lean /etc/xdg/hc-arc && lean /usr/bin/hc-a"
dpkg -i "$W/hc-a_1.0_all.deb" </dev/null >"$W/c2.log" 2>&1 || bad "C: second reinstall: $(tail -3 "$W/c2.log")"
check "C: in the same second as the last: projected again" bash -c "$(declare -f lean); lean /etc/xdg/hc-arc && lean /usr/bin/hc-a"
settle
dpkg -i "$W/hc-a_1.0_all.deb" </dev/null >"$W/c3.log" 2>&1 || bad "C: third reinstall: $(tail -3 "$W/c3.log")"
check "C: after a calm run: projected again" bash -c "$(declare -f lean); lean /etc/xdg/hc-arc && lean /usr/bin/hc-a"
check "C: the script runs the same" [ "$(/usr/bin/hc-a)" = "hc-a 1.0" ]

echo "== D. an upgrade unpacked in one run, configured in the next"
settle
dpkg --unpack "$W/hc-a_1.1_all.deb" </dev/null >"$W/d1.log" 2>&1 || bad "D: unpack: $(tail -3 "$W/d1.log")"
dpkg --configure -a </dev/null >"$W/d2.log" 2>&1
check "D: configured without a prompt" sh -c "[ \"\$(dpkg-query -W -f '\${Version} \${Status}' hc-a)\" = '1.1 install ok installed' ]"
check "D: the new conffile arrived" grep -qx 'Mode=1.1' /etc/xdg/hc-arc
check "D: no .dpkg-dist, .dpkg-old or .dpkg-new" sh -c "! ls /etc/xdg/hc-arc.dpkg-* /etc/sysctl.d/90-hc-a.conf.dpkg-* >/dev/null 2>&1"
check "D: projected" bash -c "$(declare -f lean); lean /etc/xdg/hc-arc && lean /usr/bin/hc-a"

echo "== E. a package left unpacked with its records, then configured"
settle
DPKG_STEREO_DISABLE=1 dpkg --unpack "$W/hc-a_1.0_all.deb" </dev/null >"$W/e1.log" 2>&1 || bad "E: unpack with the hooks off: $(tail -3 "$W/e1.log")"
check "E: control: hc-a unpacked, its conffile lean, its records kept" sh -c "[ \"\$(dpkg-query -W -f '\${Status}' hc-a)\" = 'install ok unpacked' ] && ! grep -q commentary /etc/xdg/hc-arc && grep -q '^/etc/xdg/hc-arc	' /var/lib/dpkg-stereo/records/hc-a.tsv"
dpkg --configure -a </dev/null >"$W/e2.log" 2>&1
check "E: configured without a prompt" sh -c "[ \"\$(dpkg-query -W -f '\${Version} \${Status}' hc-a)\" = '1.0 install ok installed' ]"
check "E: the conffile of the version configured arrived" grep -qx 'Mode=1.0' /etc/xdg/hc-arc
check "E: no .dpkg-dist, .dpkg-old or .dpkg-new" sh -c "! ls /etc/xdg/hc-arc.dpkg-* /etc/sysctl.d/90-hc-a.conf.dpkg-* >/dev/null 2>&1"
check "E: projected" bash -c "$(declare -f lean); lean /etc/xdg/hc-arc && lean /usr/bin/hc-a"
dpkg-stereo --verify hc-a >"$W/verify-e.log" 2>&1
check "E: verify clean" grep -q ' 0 problems' "$W/verify-e.log"

echo "== G. a hook's kept problem goes with the next run that succeeds"
check "no hook errors before G" test ! -s /var/lib/dpkg-stereo/error.log
T=/var/lib/dpkg-stereo/packages.tsv
mv $T $T.aside && mkdir $T
dpkg --configure -a </dev/null >"$W/g1.log" 2>&1 || bad "G: dpkg stopped by a failing hook: $(tail -3 "$W/g1.log")"
errors=$(stat -c %s /var/lib/dpkg-stereo/error.log 2>/dev/null || echo 0)
dpkg-stereo --problems >"$W/g2.log" 2>&1; rc=$?
check "G: control: the failing post-invoke kept its problem" sh -c "[ $rc = 1 ] && grep -q 'IsADirectoryError' '$W/g2.log'"
rmdir $T && mv $T.aside $T
dpkg --configure -a </dev/null >"$W/g3.log" 2>&1
dpkg-stereo --problems >"$W/g4.log" 2>&1; rc=$?
check "G: the next run that succeeds clears it" [ $rc = 0 ]
dpkg --configure -a </dev/null >"$W/g5.log" 2>&1
dpkg-stereo --problems >"$W/g6.log" 2>&1; rc=$?
check "G: and the run after keeps none" [ $rc = 0 ]
check "G: no hook error after the fix" [ "$(stat -c %s /var/lib/dpkg-stereo/error.log 2>/dev/null || echo 0)" = "$errors" ]

echo "== F. a removal and a purge"
dpkg -r hc-a </dev/null >"$W/f1.log" 2>&1 || bad "F: remove: $(tail -3 "$W/f1.log")"
dpkg -P hc-a hc-b </dev/null >"$W/f2.log" 2>&1 || bad "F: purge: $(tail -3 "$W/f2.log")"
check "F: the conffiles gone with the purge" sh -c "! ls /etc/xdg/hc-arc /etc/xdg/hc-brc /etc/sysctl.d/90-hc-a.conf /etc/sysctl.d/90-hc-b.conf >/dev/null 2>&1"
check "F: nothing of hc-a or hc-b recorded or left" sh -c "! ls /var/lib/dpkg-stereo/records /var/lib/dpkg-stereo/left 2>/dev/null | grep -q '^hc-' && ! grep -q '^/etc/xdg/hc-' /var/lib/dpkg-stereo/conffiles.tsv"
dpkg --audit >"$W/audit.log" 2>&1
check "dpkg --audit empty" test ! -s "$W/audit.log"
echo "SUMMARY: $passed passed, $failed failed"
exit $fail
