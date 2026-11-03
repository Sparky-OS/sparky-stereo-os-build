#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# A package that a dpkg run leaves in another state than "installed" with its files in place keeps its records
# (ORDER 367), in a throwaway Debian container (root) with the edition's dpkg and dpkg-stereo installed:
#   A. triggers-pending: a package whose file trigger an install activates in a run with --no-triggers (as apt's runs
#      leave systemd whenever a package ships a file in /usr/lib/systemd/catalog) keeps its records through that run
#      and the run that processes the trigger: its lean files stay recorded, nothing is called "changed since its
#      package installed it", and --restore brings its files back
#   B. half-configured: a package another package's unpack deconfigures (--auto-deconfigure, a Breaks) keeps its
#      records until it is configured again
# 0.1.28 and older counted only "installed": the records went, and the lean files stayed unrecorded.
# Usage: trigger-states-test.sh WORKDIR
set -u
W=$1
export DEBIAN_FRONTEND=noninteractive
fail=0 passed=0 failed=0
ok() { echo "PASS $*"; passed=$((passed + 1)); }
bad() { echo "FAIL $*"; fail=1; failed=$((failed + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
lean() { ! grep -q 'commentary' "$1"; }
recorded() { grep -q "^$2	" "/var/lib/dpkg-stereo/records/$1.tsv" 2>/dev/null; }
md5ok() { [ "$(md5sum <"$2" | cut -d' ' -f1)" = "$(grep "  ${2#/}\$" "/var/lib/dpkg/info/$1.md5sums" | cut -c1-32)" ]; }
mk() {   # mk NAME VERSION [CONTROL-LINES] [TRIGGERS]
	d=$W/src/$1-$2
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/usr/bin" "$d/etc/xdg"
	printf '#!/bin/sh\n# %s %s: commentary the shell skips at every start.\n# A second line of commentary.\necho "%s %s"\n' "$1" "$2" "$1" "$2" >"$d/usr/bin/$1"
	chmod 755 "$d/usr/bin/$1"
	printf '# %s defaults: commentary for people; KConfig reads groups and keys only.\n# A second line of commentary.\n[General]\nMode=fast\n' "$1" >"$d/etc/xdg/$1rc"
	printf '/etc/xdg/%src\n' "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\n%bDescription: trigger states test\n' "$1" "$2" "${3:-}" >"$d/DEBIAN/control"
	if [ -n "${4:-}" ]; then
		printf '%s\n' "$4" >"$d/DEBIAN/triggers"
		printf '#!/bin/sh\nexit 0\n' >"$d/DEBIAN/postinst"
		chmod 755 "$d/DEBIAN/postinst"
	fi
	dpkg-deb --root-owner-group -b "$d" "$W/$1_$2_all.deb" >/dev/null
}
command -v dpkg-stereo >/dev/null || { echo "dpkg-stereo is not installed: install it (and the edition's dpkg) first"; exit 2; }
rm -rf "$W"
mkdir -p "$W"

echo "== A. triggers-pending between two runs"
mk ts-watch 1.0 '' 'interest-noawait /usr/share/ts-watched'
d=$W/src/ts-feed; mkdir -p "$d/DEBIAN" "$d/usr/share/ts-watched"
echo data >"$d/usr/share/ts-watched/feed.txt"
printf 'Package: ts-feed\nVersion: 1.0\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: activates ts-watch\n' >"$d/DEBIAN/control"
dpkg-deb --root-owner-group -b "$d" "$W/ts-feed_1.0_all.deb" >/dev/null
dpkg -i "$W/ts-watch_1.0_all.deb" </dev/null >"$W/a1.log" 2>&1 || bad "A: install ts-watch: $(tail -3 "$W/a1.log")"
check "A: control: ts-watch's script lean and recorded" bash -c "$(declare -f lean recorded); lean /usr/bin/ts-watch && recorded ts-watch /usr/bin/ts-watch"
dpkg --no-triggers -i "$W/ts-feed_1.0_all.deb" </dev/null >"$W/a2.log" 2>&1 || bad "A: install ts-feed: $(tail -3 "$W/a2.log")"
check "A: control: ts-watch's trigger pending" [ "$(dpkg-query -W -f '${Status}' ts-watch)" = "install ok triggers-pending" ]
check "A: its script still recorded while the trigger is pending" bash -c "$(declare -f recorded); recorded ts-watch /usr/bin/ts-watch"
check "A: its conffile still recorded" bash -c "$(declare -f recorded); recorded ts-watch /etc/xdg/ts-watchrc"
dpkg --triggers-only -a </dev/null >"$W/a3.log" 2>&1 || bad "A: dpkg --triggers-only -a: $(tail -3 "$W/a3.log")"
check "A: control: ts-watch installed again" [ "$(dpkg-query -W -f '${Status}' ts-watch)" = "install ok installed" ]
check "A: its script lean and recorded" bash -c "$(declare -f lean recorded); lean /usr/bin/ts-watch && recorded ts-watch /usr/bin/ts-watch"
check "A: nothing of it called changed since its package installed it" sh -c "! grep -q 'changed since its package installed it' /var/lib/dpkg-stereo/left/ts-watch.tsv 2>/dev/null"
dpkg-stereo --verify ts-watch >"$W/verify-a.log" 2>&1
check "A: verify clean" grep -q ' 0 problems' "$W/verify-a.log"
cp "$W/ts-watch_1.0_all.deb" /var/cache/apt/archives/
dpkg-stereo --restore ts-watch >"$W/restore-a.log" 2>&1
check "A: --restore brings its script back in its package's bytes" bash -c "$(declare -f md5ok); md5ok ts-watch /usr/bin/ts-watch"
dpkg -P ts-feed ts-watch </dev/null >"$W/a4.log" 2>&1

echo "== B. half-configured: deconfigured by another package's unpack"
mk ts-old 1.0 'Depends: ts-base\n'
mk ts-base 1.0
mk ts-base 2.0 'Breaks: ts-old (<< 2.0)\n'
dpkg -i "$W/ts-base_1.0_all.deb" "$W/ts-old_1.0_all.deb" </dev/null >"$W/b1.log" 2>&1 || bad "B: install: $(tail -3 "$W/b1.log")"
check "B: control: ts-old's script lean and recorded" bash -c "$(declare -f lean recorded); lean /usr/bin/ts-old && recorded ts-old /usr/bin/ts-old"
dpkg --auto-deconfigure -i "$W/ts-base_2.0_all.deb" </dev/null >"$W/b2.log" 2>&1
check "B: control: ts-old deconfigured" [ "$(dpkg-query -W -f '${Status}' ts-old)" = "install ok half-configured" ]
check "B: its script still recorded while deconfigured" bash -c "$(declare -f recorded); recorded ts-old /usr/bin/ts-old"
dpkg -i "$W/ts-base_1.0_all.deb" </dev/null >"$W/b3.log" 2>&1
dpkg --configure -a </dev/null >"$W/b4.log" 2>&1
check "B: control: ts-old installed again" [ "$(dpkg-query -W -f '${Status}' ts-old)" = "install ok installed" ]
check "B: its script lean and recorded" bash -c "$(declare -f lean recorded); lean /usr/bin/ts-old && recorded ts-old /usr/bin/ts-old"
check "B: nothing of it called changed since its package installed it" sh -c "! grep -q 'changed since its package installed it' /var/lib/dpkg-stereo/left/ts-old.tsv 2>/dev/null"
dpkg-stereo --verify ts-old ts-base >"$W/verify-b.log" 2>&1
check "B: verify clean" grep -q ' 0 problems' "$W/verify-b.log"
dpkg -P ts-old ts-base </dev/null >"$W/b5.log" 2>&1
dpkg --audit >"$W/audit.log" 2>&1
check "dpkg --audit empty" test ! -s "$W/audit.log"
check "no hook errors" test ! -s /var/lib/dpkg-stereo/error.log
echo "SUMMARY: $passed passed, $failed failed"
exit $fail
