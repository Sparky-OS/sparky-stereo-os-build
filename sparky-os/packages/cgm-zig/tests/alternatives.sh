#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
# The edition's zig stays the zig with another zig installed too (ORDER 361), in a disposable container as root with
# Debian's archive configured: the Debian Zig Team's packaging (zig, which owns /usr/bin/zig, and zig0.16) installed
# after this package and before it, reinstalled, this package removed and purged, and an upgrade from an earlier
# cgm-zig. Prints PASS and FAIL lines and exits 1 on any FAIL.
#   alternatives.sh CGM_ZIG_DEB OTHER_ZIG_DIR [EARLIER_CGM_ZIG_DEB]
# OTHER_ZIG_DIR holds zig_*.deb, zig0.16_*.deb and zig0.16-dev_*.deb.
set -u
NEW=$(realpath "${1:?Usage: alternatives.sh CGM_ZIG_DEB OTHER_ZIG_DIR [EARLIER_CGM_ZIG_DEB]}")
OTHER=$(realpath "${2:?Usage: alternatives.sh CGM_ZIG_DEB OTHER_ZIG_DIR [EARLIER_CGM_ZIG_DEB]}")
OLD=${3:+$(realpath "$3")}
OURS=/usr/lib/cgm-zig/bin/zig
VERSION=0.16.0+cgm.0399d2b19b
export DEBIAN_FRONTEND=noninteractive
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "PASS  $*"; }
no() { fail=$((fail + 1)); echo "FAIL  $*"; }
check() { if eval "$2"; then ok "$1"; else no "$1 ($3)"; fi; }
apt_in() { apt-get -y -q install "$@" >/tmp/apt.log 2>&1 || { tail -n 20 /tmp/apt.log; return 1; }; }
theirs_debs() { echo "$OTHER"/zig_*.deb "$OTHER"/zig0.16_*.deb "$OTHER"/zig0.16-dev_*.deb; }
theirs=$(dpkg-deb --fsys-tarfile "$OTHER"/zig_*.deb | tar -tv | sed -n 's|.* \./usr/bin/zig -> \.\./|/usr/|p')

ours() {
	check "$1: /usr/bin/zig is the edition's zig" '[ "$(readlink -f /usr/bin/zig)" = $OURS ]' "it is $(readlink -f /usr/bin/zig 2>/dev/null)"
	check "$1: zig version is $VERSION" '[ "$(zig version 2>/dev/null)" = $VERSION ]' "it says $(zig version 2>&1 | head -n 1)"
	check "$1: update-alternatives names it best" \
		'update-alternatives --query zig | grep -qx "Best: $OURS"' "$(update-alternatives --query zig 2>&1 | grep Best)"
}
reachable() {
	check "$1: the other zig keeps its own name (zig0.16)" '/usr/bin/zig0.16 version >/dev/null 2>&1' "zig0.16 does not run"
	check "$1: its /usr/bin/zig is diverted to /usr/bin/zig.distrib" '[ "$(readlink -f /usr/bin/zig.distrib)" = "$theirs" ]' \
		"zig.distrib is $(readlink -f /usr/bin/zig.distrib 2>/dev/null)"
}
clean_audit() {
	check "$1: dpkg --audit is empty" '[ -z "$(dpkg --audit)" ]' "$(dpkg --audit | head -n 3)"
}

echo "== the other zig: $(theirs_debs | xargs -n1 basename | tr '\n' ' '), its /usr/bin/zig -> $theirs"
apt-get -q update >/dev/null 2>&1

echo "-- 1. this package first, then the other zig"
apt_in "$NEW" || no "install $NEW"
ours "alone"
check "alone: /usr/bin/zig is diverted for other packages" '[ "$(dpkg-divert --listpackage /usr/bin/zig)" = cgm-zig ]' \
	"diverted by '$(dpkg-divert --listpackage /usr/bin/zig)'"
apt_in $(theirs_debs) || no "install the other zig"
ours "the other zig installed after it"
reachable "the other zig installed after it"
apt-get -y -q install --reinstall "$OTHER"/zig_*.deb >/tmp/apt.log 2>&1 || no "reinstall the other zig"
ours "the other zig reinstalled"
clean_audit "case 1"
apt-get -y -q remove cgm-zig >/tmp/apt.log 2>&1 || no "remove cgm-zig"
check "cgm-zig removed: /usr/bin/zig is the other zig again" '[ "$(readlink -f /usr/bin/zig)" = "$theirs" ]' \
	"it is $(readlink -f /usr/bin/zig 2>/dev/null)"
check "cgm-zig removed: no diversion and no zig.distrib" '[ -z "$(dpkg-divert --listpackage /usr/bin/zig)" ] && [ ! -e /usr/bin/zig.distrib ] && [ ! -L /usr/bin/zig.distrib ]' \
	"diversion '$(dpkg-divert --listpackage /usr/bin/zig)'"
check "cgm-zig removed: the zig alternative is gone" '! update-alternatives --query zig >/dev/null 2>&1' "it is still registered"
clean_audit "cgm-zig removed"
apt-get -y -q purge cgm-zig zig zig0.16 zig0.16-dev >/tmp/apt.log 2>&1 || no "purge everything"
check "everything purged: no /usr/bin/zig" '[ ! -e /usr/bin/zig ] && [ ! -L /usr/bin/zig ]' "$(ls -l /usr/bin/zig 2>&1)"

echo "-- 2. the other zig first, then this package"
apt_in $(theirs_debs) || no "install the other zig"
check "the other zig alone: /usr/bin/zig is its own" '[ "$(readlink -f /usr/bin/zig)" = "$theirs" ]' "it is $(readlink -f /usr/bin/zig)"
apt_in "$NEW" || no "install $NEW"
ours "this package installed after the other zig"
reachable "this package installed after the other zig"
clean_audit "case 2"
apt-get -y -q purge cgm-zig >/tmp/apt.log 2>&1 || no "purge cgm-zig"
check "cgm-zig purged: /usr/bin/zig is the other zig's again" '[ "$(readlink -f /usr/bin/zig)" = "$theirs" ]' \
	"it is $(readlink -f /usr/bin/zig 2>/dev/null)"
check "cgm-zig purged: dpkg -S names the other zig for /usr/bin/zig" 'dpkg -S /usr/bin/zig 2>/dev/null | grep -qx "zig: /usr/bin/zig"' \
	"$(dpkg -S /usr/bin/zig 2>&1)"
clean_audit "cgm-zig purged"
apt-get -y -q purge zig zig0.16 zig0.16-dev >/tmp/apt.log 2>&1

if [ -n "$OLD" ]; then
	echo "-- 3. an upgrade from $(basename "$OLD") with the other zig installed"
	apt_in "$OLD" || no "install $OLD"
	apt_in $(theirs_debs) || no "install the other zig"
	echo "   before the upgrade /usr/bin/zig is $(readlink -f /usr/bin/zig)"
	apt_in "$NEW" || no "upgrade to $NEW"
	ours "upgraded"
	reachable "upgraded"
	clean_audit "case 3"
	apt-get -y -q purge cgm-zig zig zig0.16 zig0.16-dev >/tmp/apt.log 2>&1
fi
echo "SUMMARY $pass PASS, $fail FAIL"
[ "$fail" = 0 ]
