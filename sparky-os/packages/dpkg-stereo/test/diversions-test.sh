#!/bin/sh
# Rows 629 and 802: a file under a dpkg diversion. dpkg keeps the diverting package's own copy at the path and every
# other package's copy at the diverted name (dpkg-divert(1), --package), so dpkg-stereo judges the owner's copy where
# dpkg keeps it, against the owner's record, and the diverting package's copy at the path as that package's (here an
# lc1 package, as every package of the edition is). A person's edit at either place still fails and is kept; a
# diversion removed again; the owner upgraded under the diversion; restore. And, beside it, a projected conffile that is
# the same in two versions of its package keeps its record, so a later version that changes it is not taken for the
# person's edit (dpkg asked "Modified locally since installation" about a file nobody touched).
# Usage: diversions-test.sh DPKG-STEREO.deb WORKDIR   (a throwaway container, root, no network, the published edition
# installed: dpkg 1.23.11+stereo3d3+lc1 and a dpkg-stereo; DEB is the one under test)
# Red on 0.1.41 and 0.1.42, green on 0.1.43. Every scenario ends with its packages purged.
set -u
DEB=$1 W=$2
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
check() { # check DESCRIPTION COMMAND...
	d=$1; shift
	if "$@"; then ok "$d"; else bad "$d"; fi
}
mkdir -p "$W"
C=/etc/sysctl.d/93-dv-demo.conf      # dv-owner's conffile, which dv-replace diverts
D=/etc/sysctl.d/93-dv-demo.conf.dv-owner   # where dpkg keeps dv-owner's copy under the diversion
owner() { # owner VERSION VALUE: one conffile with commentary, which dpkg-stereo projects
	d=$W/dv-owner-$1
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/sysctl.d"
	printf '# dv-owner: the package that owns this setting.\n# Commentary the kernel never reads.\nvm.swappiness = %s\n' "$2" >"$d$C"
	printf '%s\n' "$C" >"$d/DEBIAN/conffiles"
	printf 'Package: dv-owner\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: owner of a diverted conffile\n' "$1" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/dv-owner_$1_all.deb" >/dev/null
}
replacement() { # dv-replace 1.0: an lc1 package that diverts dv-owner's conffile and puts its own file at its name
	d=$W/dv-replace
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/sysctl.d"
	printf '# dv-replace: the value of the package that diverts the owner'"'"'s file.\n# More commentary the kernel never reads, so it goes.\nvm.swappiness = 77\n' >"$d$C"
	printf 'Package: dv-replace\nVersion: 1.0\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: diverts a conffile\n' >"$d/DEBIAN/control"
	cat >"$d/DEBIAN/preinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = install ] || [ "\$1" = upgrade ]; then
	dpkg-divert --package dv-replace --add --rename --divert $D $C
fi
EOF
	cat >"$d/DEBIAN/postrm" <<EOF
#!/bin/sh
set -e
if [ "\$1" = remove ] || [ "\$1" = abort-install ]; then
	dpkg-divert --package dv-replace --remove --rename --divert $D $C
fi
EOF
	chmod 755 "$d/DEBIAN/preinst" "$d/DEBIAN/postrm"
	rm -rf "$W/dv-replace-hr"   # lean.package.prepare makes it (it refuses one that exists)
	PYTHONPATH=/usr/lib/dpkg-stereo python3 -c 'import sys; from lean import package; package.prepare(sys.argv[1], sys.argv[2])' \
		"$d" "$W/dv-replace-hr" >"$W/seal.log" 2>&1 || bad "the lc1 fixture could not be sealed: $(tail -2 "$W/seal.log")"
	dpkg-deb --root-owner-group -b "$d" "$W/dv-replace_1.0_all.deb" >/dev/null
}
uc() { # uc VERSION VALUE: a package whose projected conffile is the same in 1.0 and 2.0 and changes in 3.0
	d=$W/uc-demo-$1
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/sysctl.d"
	printf '# uc-demo: a setting that is the same in two versions of its package.\n# More commentary the kernel never reads, so it goes.\nvm.dirty_ratio = %s\n' "$2" >"$d/etc/sysctl.d/94-uc-demo.conf"
	printf '/etc/sysctl.d/94-uc-demo.conf\n' >"$d/DEBIAN/conffiles"
	printf 'Package: uc-demo\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: unchanged conffile\n' "$1" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/uc-demo_$1_all.deb" >/dev/null
}
lean() { head -1 "$1" | grep -q 'Lean Code'; }
verify() { dpkg-stereo --verify dv-owner dv-replace >"$W/v.log" 2>&1; echo $? >"$W/v.rc"; }
clean() { [ "$(cat "$W/v.rc")" = 0 ] && ! grep -q '^\(CHANGED\|LCCHANGED\|STALE\|MISSING\|MISMATCH\|PRISTINE\)' "$W/v.log"; }
says() { grep -q -- "$1" "$W/v.log"; }
show() { sed 's/^/    /' "$W/v.log"; }
dpki() { dpkg "$@" </dev/null >"$W/dpkg.log" 2>&1; }
asked() { grep -qi 'Modified locally\|configuration file' "$W/dpkg.log"; }

dpkg -i "$DEB" </dev/null >"$W/install.log" 2>&1 || bad "installing $DEB: $(tail -3 "$W/install.log")"
echo "== dpkg-stereo under test: $(dpkg-query -W -f='${Version}' dpkg-stereo); dpkg $(dpkg-query -W -f='${Version}' dpkg)"
owner 1.0 10; owner 2.0 10; owner 3.0 30; owner 4.0 40; replacement

echo "== 1. the owner first, then the diversion (row 802: bash's .bashrc and sparky-stereo-console)"
dpki -i "$W/dv-owner_1.0_all.deb" || bad "dv-owner 1.0: $(tail -2 "$W/dpkg.log")"
check "the owner's conffile is projected" lean $C
dpki -i "$W/dv-replace_1.0_all.deb" || bad "dv-replace: $(tail -2 "$W/dpkg.log")"
check "the diversion moved the owner's lean copy aside" lean $D
cp -p $C "$W/replacement.bak"; cp -p $D "$W/owner.bak"
verify; show
check "untouched: --verify is clean (it called the owner's record 'changed by the person')" clean

echo "== 2. the person edits the diverting package's file at the path"
printf 'vm.swappiness = 5\n' >>$C
verify; show
check "the edited replacement is named as its own package's (LCCHANGED)" says "^LCCHANGED $C "
check "and nothing is said of the owner's copy, which nobody touched" sh -c "! grep -q '^CHANGED' '$W/v.log'"
cp -p "$W/replacement.bak" $C

echo "== 3. the person edits the owner's copy, where dpkg keeps it"
printf 'vm.swappiness = 6\n' >>$D
verify; show
check "the edited original fails, named at its place" says "^CHANGED   $C (changed by the person, at $D"
cp -p "$W/owner.bak" $D
verify
check "back to the owner's lean bytes: clean again" clean

echo "== 4. the owner upgraded under the diversion, its conffile the same (2.0)"
dpki -i "$W/dv-owner_2.0_all.deb"; rc=$?
check "upgrade exit 0" [ $rc = 0 ]
check "dpkg did not ask" sh -c "! grep -qi 'Modified locally\|configuration file' '$W/dpkg.log'"
check "the owner's copy is still lean, where dpkg keeps it" lean $D
check "the record follows the new version" grep -q "^$C	dv-owner	2.0	1	" /var/lib/dpkg-stereo/records/dv-owner.tsv
verify; show
check "--verify is clean" clean

echo "== 5. the owner upgraded under the diversion, its conffile changed (3.0)"
dpki -i "$W/dv-owner_3.0_all.deb"; rc=$?
check "upgrade exit 0" [ $rc = 0 ]
check "dpkg did not ask" sh -c "! grep -qi 'Modified locally\|configuration file' '$W/dpkg.log'"
check "the owner's copy is version 3.0" grep -q 'vm.swappiness = 30' $D
check "and projected again where dpkg keeps it" lean $D
check "the replacement is untouched" cmp -s $C "$W/replacement.bak"
check "no .dpkg-new or .dpkg-dist left" sh -c "! ls $C.* $D.* 2>/dev/null | grep -q 'dpkg-'"
verify; show
check "--verify is clean" clean

echo "== 6. restore under the diversion: the owner's original comes back where dpkg keeps it"
dpkg-stereo --restore dv-owner >"$W/restore.log" 2>&1; cat "$W/restore.log"
check "the owner's copy is its package's bytes again" grep -q 'Commentary the kernel never reads' $D
check "the replacement is untouched" cmp -s $C "$W/replacement.bak"
dpkg-stereo --project dv-owner >"$W/project.log" 2>&1
check "projected again" lean $D
verify
check "--verify is clean" clean

echo "== 7. the diversion removed again"
dpki -r dv-replace || bad "removing dv-replace: $(tail -2 "$W/dpkg.log")"
check "the owner's lean copy is back at its name" lean $C
check "nothing left at the diverted name" [ ! -e $D ]
verify; show
check "--verify is clean" clean

echo "== 8. a person's edit of the owner's copy is kept through an upgrade and the diversion's removal"
dpki -i "$W/dv-replace_1.0_all.deb" || bad "dv-replace again"
printf 'vm.swappiness = 7\n' >>$D
cp -p $D "$W/edited.bak"
dpki --force-confold -i "$W/dv-owner_4.0_all.deb"; rc=$?
check "upgrade with the person's edit, --force-confold: exit 0" [ $rc = 0 ]
check "the person's edit is kept" cmp -s $D "$W/edited.bak"
verify; show
# after an upgrade, a person's edit of a conffile is named as EDITED (left as they made it), as for every conffile; a copy
# at a diverted name says where it is, in its own parentheses before the line's fixed end (0.1.45)
check "--verify names the edit at its diverted name" says "^EDITED    $C (at $D: dv-owner's copy, diverted by dv-replace) (changed by the person: left as they made it)$"
dpki -r dv-replace || bad "removing dv-replace"
check "the edit moved back with the owner's copy" cmp -s $C "$W/edited.bak"
verify; show
check "--verify still names the edit, now undiverted" says "^EDITED    $C (changed by the person: left as they made it)$"
dpki --purge dv-owner dv-replace

echo "== 9. the diversion first, then the owner: its conffile is projected where dpkg keeps it"
dpki -i "$W/dv-replace_1.0_all.deb" || bad "dv-replace"
dpki -i "$W/dv-owner_1.0_all.deb" || bad "dv-owner 1.0"
check "the owner's copy is at the diverted name" [ -f $D ]
check "and projected there" lean $D
check "the replacement is its own package's file" cmp -s $C "$W/replacement.bak"
verify; show
check "--verify is clean" clean
dpki --purge dv-owner dv-replace

echo "== 10. a projected conffile the same in two versions keeps its record (no diversion)"
uc 1.0 20; uc 2.0 20; uc 3.0 30
dpki -i "$W/uc-demo_1.0_all.deb"; dpki -i "$W/uc-demo_2.0_all.deb"
check "after 2.0 the record is there, under 2.0" grep -q '^/etc/sysctl.d/94-uc-demo.conf	uc-demo	2.0	1	' /var/lib/dpkg-stereo/records/uc-demo.tsv
dpki -i "$W/uc-demo_3.0_all.deb"; rc=$?
check "3.0, which changes the conffile: exit 0" [ $rc = 0 ]
check "dpkg did not ask" sh -c "! grep -qi 'Modified locally\|configuration file' '$W/dpkg.log'"
check "the conffile is version 3.0" grep -q 'vm.dirty_ratio = 30' /etc/sysctl.d/94-uc-demo.conf
check "and projected" lean /etc/sysctl.d/94-uc-demo.conf
check "no .dpkg-new left" [ ! -e /etc/sysctl.d/94-uc-demo.conf.dpkg-new ]
dpkg-stereo --verify uc-demo >"$W/uc.log" 2>&1 && ok "--verify uc-demo is clean" || bad "--verify uc-demo: $(cat "$W/uc.log")"
dpki --purge uc-demo

[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
