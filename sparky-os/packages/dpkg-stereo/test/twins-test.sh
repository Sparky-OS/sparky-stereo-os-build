#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# dpkg-stereo 0.1.27 with the edition's dpkg (1.23.11+stereo3d1+lc1) and the shared files of a Multi-Arch: same package
# (ORDER 363), in a throwaway Debian container (root) where both are installed and dpkg has i386: a package for amd64 and
# i386 whose /usr/share scripts and conffile both architectures share is built here; its amd64 instance is installed and
# projected, the person edits its conffile; then the i386 instance installs, both reinstall, the recorded instance is
# removed and installed again, and both are purged. Every shared file stays projected and recorded once, as on disk, the
# person's edit stays, dpkg --audit stays empty. The controls must fail: a twin whose shared file really differs, a record
# naming that file as the original, and a projection changed after its record are refused with dpkg's own message.
# Usage: twins-test.sh WORKDIR
set -u
W=$1
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
sha() { sha256sum <"$1" | cut -d' ' -f1; }
md5() { md5sum <"$1" | cut -d' ' -f1; }
lean() {   # lean INSTANCE PATH: not the package's bytes, and the lean form's pointer line
	[ "$(md5 "$2")" != "$(grep "  ${2#/}\$" "/var/lib/dpkg/info/$1.md5sums" | cut -c1-32)" ] && grep -q 'Lean Code:' "$2"
}
recorded() {   # PATH recorded once, for one instance, as the projection on disk
	[ "$(grep -l "^$1	" /var/lib/dpkg-stereo/records/*.tsv 2>/dev/null | wc -l)" = 1 ] &&
		grep -h "^$1	" /var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' -v s="$(sha "$1")" '$7 == s { f = 1 } END { exit !f }'
}
mk() {   # mk NAME VERSION ARCH NOTE
	d=$W/src/$1_$2_$3
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/usr/share/$1" "$d/etc/xdg"
	cat >"$d/usr/share/$1/tool.py" <<PY
#!/usr/bin/python3
# $1 $2: a script every architecture's package ships at this path, so dpkg shares it.
# These lines are for people; the interpreter skips them at every start and Lean Code removes them.
# One more line of commentary, so the pointer line is the smaller one.
print("$1 $2$4")
PY
	cat >"$d/usr/share/$1/run.sh" <<SH
#!/bin/sh
# $1 $2: a shared shell script; the shell skips these lines at every start.
# Lean Code removes them; this one makes the comments longer than the pointer line.
echo "$1 $2"
SH
	printf '# %s defaults, the same in every architecture; the person edits this one.\n# KConfig reads groups and keys only.\n[General]\nMode=fast\n' "$1" >"$d/etc/xdg/$1rc"
	printf '/etc/xdg/%src\n' "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMulti-Arch: same\nMaintainer: test <t@example.org>\nDescription: shared files test\n' "$1" "$2" "$3" >"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/$1_$2_$3.deb" >/dev/null
}
command -v dpkg-stereo >/dev/null || { echo "dpkg-stereo is not installed: install it (and the edition's dpkg) first"; exit 2; }
dpkg-query -W -f '${Provides}' dpkg | grep -q 'dpkg-lean-code' || { echo "dpkg is not the edition's (no dpkg-lean-code)"; exit 2; }
rm -rf "$W"
mkdir -p "$W"
dpkg --print-foreign-architectures | grep -qx i386 || dpkg --add-architecture i386
for a in amd64 i386; do mk twin-demo 1.0 $a ''; done
mk differs-demo 1.0 amd64 ' (amd64)'
mk differs-demo 1.0 i386 ' (i386)'
T=/usr/share/twin-demo/tool.py RC=/etc/xdg/twin-demorc
echo "== the amd64 instance, projected after its dpkg run; the person edits the conffile"
dpkg -i "$W/twin-demo_1.0_amd64.deb" </dev/null >"$W/a.log" 2>&1 && ok "amd64 install" || bad "amd64 install: $(tail -3 "$W/a.log")"
lean twin-demo:amd64 $T && ok "shared script projected" || bad "shared script not projected"
printf 'Edited=by the person\n' >>$RC
echo "== the i386 instance: a new instance of the same version"
dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/b.log" 2>&1 && ok "i386 installs" || bad "i386 install: $(grep -m1 'trying to overwrite' "$W/b.log")"
lean twin-demo:amd64 $T && recorded $T && ok "projected again and recorded once" || bad "after the i386 install: $(grep -h "^$T	" /var/lib/dpkg-stereo/records/*.tsv)"
echo "== reinstall each"
dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/c.log" 2>&1 && ok "i386 reinstalls" || bad "i386 reinstall"
dpkg -i "$W/twin-demo_1.0_amd64.deb" </dev/null >"$W/d.log" 2>&1 && ok "amd64 reinstalls" || bad "amd64 reinstall"
lean twin-demo:amd64 $T && recorded $T && ok "still projected and recorded once" || bad "after the reinstalls"
echo "== remove the recorded instance: the file stays with its record, the instance installs again"
owner=$(grep -l "^$T	" /var/lib/dpkg-stereo/records/*.tsv | xargs -n1 basename | sed 's/\.tsv$//')
dpkg -r "$owner" </dev/null >"$W/e.log" 2>&1 && ok "removal of $owner" || bad "removal of $owner"
lean "$(dpkg-query -W -f '${Package}:${Architecture}\n' twin-demo:amd64 twin-demo:i386 2>/dev/null | head -n1)" $T && recorded $T &&
	ok "the record went to the other instance" || bad "after the removal: $(grep -h "^$T	" /var/lib/dpkg-stereo/records/*.tsv)"
dpkg -i "$W/twin-demo_1.0_${owner#*:}.deb" </dev/null >"$W/f.log" 2>&1 && ok "$owner installs again" || bad "$owner again: $(grep -m1 'trying to overwrite' "$W/f.log")"
grep -qx 'Edited=by the person' $RC && ok "the person's edit kept" || bad "the edit changed"
dpkg-stereo --verify twin-demo >"$W/verify.log" 2>&1
if grep -q 'projected files checked' "$W/verify.log" && ! grep -qE '^(MISSING|RESTORED|STALE|MISMATCH) ' "$W/verify.log"; then
	ok "verify: $(tail -1 "$W/verify.log")"
else bad "verify: $(cat "$W/verify.log")"; fi
echo "== purge both"
dpkg -P twin-demo:i386 </dev/null >"$W/g.log" 2>&1 && lean twin-demo:amd64 $T && recorded $T && ok "purge i386: the file stays, recorded" || bad "purge i386"
dpkg -P twin-demo:amd64 </dev/null >"$W/h.log" 2>&1 && [ ! -e $T ] && ! grep -qs "^/usr/share/twin-demo/" /var/lib/dpkg-stereo/records/*.tsv &&
	ok "purge amd64: file and records gone" || bad "purge amd64"
echo "== controls: what really differs is refused"
D=/usr/share/differs-demo/tool.py
dpkg -i "$W/differs-demo_1.0_amd64.deb" </dev/null >"$W/i.log" 2>&1
if dpkg -i "$W/differs-demo_1.0_i386.deb" </dev/null >"$W/j.log" 2>&1; then bad "a twin that differs installed"
else grep -q "trying to overwrite shared '$D', which is different from other instances of package differs-demo:i386" "$W/j.log" &&
	ok "a twin that differs: refused" || bad "refused for another reason: $(grep -m1 'dpkg:' "$W/j.log")"; fi
dpkg-deb --fsys-tarfile "$W/differs-demo_1.0_i386.deb" | tar -xO ./usr/share/differs-demo/tool.py >"$W/i386.py"
sed -i "s|^\($D	[^	]*	[^	]*	[^	]*	\)[0-9a-f]\{64\}|\1$(sha "$W/i386.py")|" /var/lib/dpkg-stereo/records/differs-demo:amd64.tsv
if dpkg -i "$W/differs-demo_1.0_i386.deb" </dev/null >"$W/k.log" 2>&1; then bad "a forged record let a different file in"
else grep -q "trying to overwrite shared '$D'" "$W/k.log" && ok "a record naming the other file as the original: refused" || bad "forged: $(grep -m1 'dpkg:' "$W/k.log")"; fi
dpkg -P differs-demo:amd64 </dev/null >/dev/null 2>&1
dpkg -i "$W/twin-demo_1.0_amd64.deb" </dev/null >/dev/null 2>&1
printf '# changed after the projection\n' >>$T
if dpkg -i "$W/twin-demo_1.0_i386.deb" </dev/null >"$W/l.log" 2>&1; then bad "a changed projection let the twin in"
else grep -q "trying to overwrite shared '$T'" "$W/l.log" && ok "a projection changed after its record: refused" || bad "changed: $(grep -m1 'dpkg:' "$W/l.log")"; fi
dpkg -P twin-demo:amd64 </dev/null >/dev/null 2>&1
dpkg --audit >"$W/audit.log" 2>&1; [ ! -s "$W/audit.log" ] && ok "dpkg --audit empty" || bad "dpkg --audit: $(cat "$W/audit.log")"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
