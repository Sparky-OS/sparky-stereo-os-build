#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# The rule for your own sysctl values, measured with systemd's own file
# ordering (systemd-analyze cat-config sysctl.d lists the files in the order
# systemd-sysctl applies them, sysctl.d(5)): 70-sparky-stereo.conf sorts
# after linux-sysctl-defaults' 50-default.conf, a file of yours numbered 71
# to 99 wins over it, a lower number loses, and a file of the same name in
# /etc/sysctl.d replaces it whole; its header states the rule. Then planted
# faults that must each fail. Runs as an ordinary user; needs systemd and
# linux-sysctl-defaults installed.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "$HERE")
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/sysctl-order.XXXXXX")}
mkdir -p "$OUT"
DEFAULT=/usr/lib/sysctl.d/50-default.conf
W=$(mktemp -d "${TMPDIR:-/tmp}/sysctl-order-work.XXXXXX")
trap 'rm -rf "$W"' EXIT
PASS=0 FAIL=0

# The value systemd-sysctl applies for key $2 under root $1: the last
# assignment in file order.
effective() {
	systemd-analyze --root="$1" cat-config sysctl.d 2>/dev/null |
		awk -v key="$2" '{ line = $0; sub(/^-/, "", line) } split(line, f, /[[:space:]]*=[[:space:]]*/) == 2 && f[1] == key { value = f[2] } END { print value }'
}

# One machine: systemd's defaults, ours under $2 (file $1), and the user's file $3 with its text $4.
machine() {
	rm -rf "$W/root"
	mkdir -p "$W/root/usr/lib/sysctl.d" "$W/root/etc/sysctl.d"
	cp "$DEFAULT" "$W/root/usr/lib/sysctl.d/"
	cp "$1" "$W/root/usr/lib/sysctl.d/$2"
	[[ -n ${3:-} ]] && printf '%s\n' "$4" >"$W/root/etc/sysctl.d/$3"
	return 0
}

cases() {
	local conf=$1 name=$2 ok=0 got
	results=()
	expect() {
		if [[ $2 == "$3" ]]; then
			results+=("PASS $1")
		else
			results+=("FAIL $1: got '$2', expected '$3'")
			ok=1
		fi
	}
	expect default-sets-max-map-count "$(grep -c '^vm.max_map_count = 1048576$' "$DEFAULT")" 1
	machine "$conf" "$name"
	expect ours-after-systemd-default "$(effective "$W/root" vm.max_map_count)" 2147483642
	expect ours-swappiness "$(effective "$W/root" vm.swappiness)" 1
	machine "$conf" "$name" 99-mine.conf 'vm.swappiness = 10'
	expect 99-mine-wins "$(effective "$W/root" vm.swappiness)" 10
	machine "$conf" "$name" 71-mine.conf 'vm.swappiness = 10'
	expect 71-mine-wins "$(effective "$W/root" vm.swappiness)" 10
	machine "$conf" "$name" 00-mine.conf 'vm.swappiness = 10'
	expect 00-mine-loses "$(effective "$W/root" vm.swappiness)" 1
	machine "$conf" "$name" 70-sparky-stereo.conf 'vm.swappiness = 30'
	expect same-name-replaces "$(effective "$W/root" vm.swappiness) $(effective "$W/root" vm.max_map_count)" "30 1048576"
	got=$(sed -n '1,/^[^#]/p' "$conf" | grep -c -e '71-\*\.conf to 99-\*\.conf' -e 'A file named 70-sparky-stereo.conf in /etc/sysctl.d replaces this one completely' -e 'sorts after 50-default.conf')
	expect header-states-the-rule "$got" 3
	return $ok
}

OURS=$PKG/usr/lib/sysctl.d/70-sparky-stereo.conf
if cases "$OURS" 70-sparky-stereo.conf; then :; fi
printf '%s\n' "${results[@]}" | tee "$OUT/sysctl-order.txt"
PASS=$(printf '%s\n' "${results[@]}" | grep -c '^PASS')
FAIL=$(printf '%s\n' "${results[@]}" | grep -c '^FAIL')

planted() {
	local name=$1 expected=$2 conf=$3 file=$4
	if cases "$conf" "$file"; then
		echo "FAIL planted-$name: not caught"
		FAIL=$((FAIL + 1))
	elif printf '%s\n' "${results[@]}" | grep -q "^FAIL $expected:"; then
		echo "PASS planted-$name: caught by $expected"
		PASS=$((PASS + 1))
	else
		echo "FAIL planted-$name: expected $expected to fail"
		FAIL=$((FAIL + 1))
	fi
}
# Ours sorting before systemd's defaults loses vm.max_map_count to them.
planted renamed-40 ours-after-systemd-default "$OURS" 40-sparky-stereo.conf
# Ours sorting last of all would beat every file of the user's.
planted renamed-zz 99-mine-wins "$OURS" zz-sparky-stereo.conf
# A header without the rule.
sed '/^# Your own values:/,/^# sorts after 50-default.conf/d' "$OURS" >"$W/no-rule.conf"
planted header-without-rule header-states-the-rule "$W/no-rule.conf" 70-sparky-stereo.conf
echo "SUMMARY: $PASS passed, $FAIL failed" | tee -a "$OUT/sysctl-order.txt"
((FAIL == 0))
