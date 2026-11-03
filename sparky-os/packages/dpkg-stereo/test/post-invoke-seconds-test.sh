#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# dpkg-stereo's post-invoke hook gives the same records whichever second dpkg and the hook ran in (ORDER 365), with the
# edition's dpkg and a Multi-Arch: same package whose /usr/share script and conffile both architectures share, in a
# throwaway Debian container (root) where both are installed and dpkg has i386. The hook looks at a package again when
# its file list's time is in the second packages.tsv was written in (the racy rule): each case runs twice, once with
# the instance's row made racy and once not, by writing packages.tsv's own columns, and both runs must end alike:
#   A. the person changes the projected script and the conffile, and the other instance is refused (our dpkg refuses a
#      shared file changed after its projection): --verify names both files, changed after their projection
#   B. both instances reinstalled, the one that holds the script's record not looking changed: the script dpkg put
#      back in its package's bytes is projected again, and recorded once
#   C. the person's conffile edit, then the other instance installs: the conffile is named once, as changed by the person
# Usage: post-invoke-seconds-test.sh WORKDIR
set -u
W=$1
export DEBIAN_FRONTEND=noninteractive
fail=0 passed=0 failed=0
ok() { echo "PASS $*"; passed=$((passed + 1)); }
bad() { echo "FAIL $*"; fail=1; failed=$((failed + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
sha() { sha256sum <"$1" | cut -d' ' -f1; }
md5() { md5sum <"$1" | cut -d' ' -f1; }
lean() {   # lean INSTANCE PATH: not the package's bytes, and the lean form's pointer line
	[ "$(md5 "$2")" != "$(grep "  ${2#/}\$" "/var/lib/dpkg/info/$1.md5sums" | cut -c1-32)" ] && grep -q 'Lean Code:' "$2"
}
recorded() {   # PATH recorded once, for one instance, as the projection on disk
	[ "$(grep -l "^$1	" /var/lib/dpkg-stereo/records/*.tsv 2>/dev/null | wc -l)" = 1 ] &&
		grep -h "^$1	" /var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' -v s="$(sha "$1")" '$7 == s { f = 1 } END { exit !f }'
}
recorded_once() { [ "$(grep -l "^$1	" /var/lib/dpkg-stereo/records/*.tsv 2>/dev/null | wc -l)" = 1 ]; }
mk() {   # mk NAME VERSION ARCH
	d=$W/src/$1_$2_$3
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/usr/share/$1" "$d/etc/xdg"
	cat >"$d/usr/share/$1/tool.py" <<PY
#!/usr/bin/python3
# $1 $2: a script every architecture's package ships at this path, so dpkg shares it.
# These lines are for people; the interpreter skips them at every start and Lean Code removes them.
# One more line of commentary, so the pointer line is the smaller one.
print("$1 $2")
PY
	printf '# %s defaults, the same in every architecture; the person edits this one.\n# KConfig reads groups and keys only.\n[General]\nMode=fast\n' "$1" >"$d/etc/xdg/$1rc"
	printf '/etc/xdg/%src\n' "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMulti-Arch: same\nMaintainer: test <t@example.org>\nDescription: shared files test\n' "$1" "$2" "$3" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/$1_$2_$3.deb" >/dev/null
}
# seconds INSTANCE racy|calm: INSTANCE's row in packages.tsv as the hook left it, but written in the second of its file
# list (racy: the next run looks at the package again) or ten seconds after it (calm: it does not)
seconds() {
	python3 - "$1" "$2" <<'PY'
import os, sys
name, mode = sys.argv[1:]
t = '/var/lib/dpkg-stereo/packages.tsv'
lines = open(t, encoding='utf-8').read().splitlines()
mtime = int(os.stat(f'/var/lib/dpkg/info/{name}.list').st_mtime)
out, found = [], False
for line in lines:
    v = line.split('\t')
    if not line.startswith('#') and v[0] == name:
        v[2], v[3] = str(mtime), str(mtime if mode == 'racy' else mtime + 10)
        found = True
    out.append('\t'.join(v))
if not found:
    sys.exit(f'{name} has no row in {t}')
open(t, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
PY
}
command -v dpkg-stereo >/dev/null || { echo "dpkg-stereo is not installed: install it (and the edition's dpkg) first"; exit 2; }
dpkg-query -W -f '${Provides}' dpkg | grep -q 'dpkg-lean-code' || { echo "dpkg is not the edition's (no dpkg-lean-code)"; exit 2; }
rm -rf "$W"
mkdir -p "$W"
dpkg --print-foreign-architectures | grep -qx i386 || dpkg --add-architecture i386
for a in amd64 i386; do mk twin-demo 1.0 $a; done
T=/usr/share/twin-demo/tool.py RC=/etc/xdg/twin-demorc
fresh() { dpkg -P twin-demo:amd64 twin-demo:i386 </dev/null >/dev/null 2>&1; rm -f $RC; }
for mode in racy calm; do
	echo "== A ($mode). the script and the conffile changed after their projection; the other instance refused"
	fresh
	dpkg -i "$W/twin-demo_1.0_amd64.deb" </dev/null >"$W/a-$mode.log" 2>&1 || bad "A $mode: amd64 install"
	lean twin-demo:amd64 $T && recorded $T || bad "A $mode: control, the script projected and recorded"
	printf '# changed after the projection\n' >>$T
	printf 'Edited=by the person\n' >>$RC
	seconds twin-demo:amd64 $mode
	dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/a2-$mode.log" 2>&1; rc=$?
	check "A $mode: the other instance refused" sh -c "[ $rc != 0 ] && grep -q \"trying to overwrite shared '$T'\" '$W/a2-$mode.log'"
	dpkg-stereo --verify twin-demo >"$W/verify-a-$mode.log" 2>&1; rc=$?
	check "A $mode: verify names the script, changed since projection" grep -qx "CHANGED   $T (changed since projection)" "$W/verify-a-$mode.log"
	check "A $mode: verify names the conffile, changed by the person" grep -qx "CHANGED   $RC (changed by the person)" "$W/verify-a-$mode.log"
	check "A $mode: verify exits 1" [ $rc = 1 ]
	check "A $mode: both recorded once" bash -c "$(declare -f recorded_once); recorded_once $T && recorded_once $RC"
	grep -E '^(CHANGED|EDITED|RESTORED|MISSING) ' "$W/verify-a-$mode.log" >"$W/named-a-$mode.txt"

	echo "== B ($mode). both instances reinstalled; the instance that holds the script's record looks $mode"
	fresh
	dpkg -i "$W/twin-demo_1.0_amd64.deb" </dev/null >"$W/b1-$mode.log" 2>&1 || bad "B $mode: amd64 install"
	dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/b2-$mode.log" 2>&1 || bad "B $mode: i386 install"
	dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/b3-$mode.log" 2>&1 || bad "B $mode: i386 reinstall"
	owner=$(grep -l "^$T	" /var/lib/dpkg-stereo/records/*.tsv | xargs -n1 basename | sed 's/\.tsv$//')
	other=twin-demo:amd64
	[ "$owner" = twin-demo:amd64 ] && other=twin-demo:i386
	seconds "$owner" $mode
	dpkg -i "$W/twin-demo_1.0_${other#*:}.deb" </dev/null >"$W/b4-$mode.log" 2>&1 || bad "B $mode: ${other#*:} reinstall"
	check "B $mode: the script projected again after $other's reinstall" lean twin-demo:amd64 $T
	check "B $mode: recorded once, as on disk" recorded $T
	dpkg -r "$(grep -l "^$T	" /var/lib/dpkg-stereo/records/*.tsv | xargs -n1 basename | sed 's/\.tsv$//')" </dev/null >"$W/b5-$mode.log" 2>&1
	check "B $mode: removing the recorded instance hands the record to the other" bash -c "$(declare -f lean recorded sha md5); lean \"\$(dpkg-query -W -f '\${Package}:\${Architecture}\n' twin-demo:amd64 twin-demo:i386 2>/dev/null | head -n1)\" $T && recorded $T"

	echo "== C ($mode). the person's conffile edit, then the other instance installs"
	fresh
	dpkg -i "$W/twin-demo_1.0_amd64.deb" </dev/null >"$W/c1-$mode.log" 2>&1 || bad "C $mode: amd64 install"
	printf 'Edited=by the person\n' >>$RC
	seconds twin-demo:amd64 $mode
	dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/c2-$mode.log" 2>&1 || bad "C $mode: i386 install"
	dpkg-stereo --verify twin-demo >"$W/verify-c-$mode.log" 2>&1
	check "C $mode: the conffile named once, changed by the person" sh -c "[ \"\$(grep -c ' $RC ' '$W/verify-c-$mode.log')\" = 1 ] && grep -qx 'CHANGED   $RC (changed by the person)' '$W/verify-c-$mode.log'"
	check "C $mode: the edit kept" grep -qx 'Edited=by the person' $RC
	check "C $mode: the script lean and recorded once" bash -c "$(declare -f lean recorded sha md5); lean twin-demo:amd64 $T && recorded $T"
	grep -E '^(CHANGED|EDITED|RESTORED|MISSING) ' "$W/verify-c-$mode.log" >"$W/named-c-$mode.txt"
done
check "A: the same files named whichever second the hook ran in" cmp -s "$W/named-a-racy.txt" "$W/named-a-calm.txt"
check "C: the same files named whichever second the hook ran in" cmp -s "$W/named-c-racy.txt" "$W/named-c-calm.txt"
dpkg --audit >"$W/audit.log" 2>&1
check "dpkg --audit empty" test ! -s "$W/audit.log"
echo "SUMMARY: $passed passed, $failed failed"
exit $fail
