#!/bin/bash
# ORDER 413 proofs, inside a clean amd64 debian:testing container that run.sh started with /run/https-only-apt.sh.
# Usage: inside.sh red|green|modified
# Never fetches over plain HTTP: the helper turned the container's sources to https; the only http:// source ever written is
# the person's test file, and it is read only while 20261104.3's block refuses it (red/green part 1) or after the new package
# converted it to https.
set -u
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
MODE=$1
FAIL=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
BLOCK=/etc/apt/apt.conf.d/00sparky-block-plain-http
OLDDEB=$(ls /old/sparky-stereo-apt_20261104.3~sparky9~0+lc1_all.deb)
case $MODE in
red) NEWDEB=$OLDDEB ;;
*) NEWDEB=$(ls /new/sparky-stereo-apt_*_all.deb | grep -v -- '-lc-hr') ;;
esac
echo "container apt before: $(dpkg-query -W -f='${Version}' apt)"
# 1. the system as the package finds it: the helper has converted the sources and trusts the host CA; install ca-certificates so
#    HTTPS keeps working once the helper's own block file (same name as the package's) is removed, then remove it: the person's
#    system never had it, the package's file is what is installed next.
apt-get update -qq >/dev/null 2>&1 || { echo "apt-get update over https failed"; exit 2; }
apt-get install -y -qq ca-certificates >/dev/null 2>&1 || { echo "ca-certificates failed"; exit 2; }
rm -f "$BLOCK"
# a stand-in for sparky-apt (SparkyLinux's repository is not in the container)
mkdir -p /tmp/standin/DEBIAN
printf 'Package: sparky-apt-standin\nVersion: 1\nArchitecture: all\nMaintainer: test <test@example.org>\nProvides: sparky-apt\nDescription: stand-in for sparky-apt\n' >/tmp/standin/DEBIAN/control
dpkg-deb --root-owner-group -b /tmp/standin /tmp/sparky-apt-standin_1_all.deb >/dev/null
KR="/old/sparky-stereo-keyring_20261016~sparky9~0+lc1_all.deb /old/deb-multimedia-keyring_2024.9.1+lc1_all.deb"
# 2. the published 20261104.3 (what a person has today)
apt-get install -y /tmp/sparky-apt-standin_1_all.deb $KR "$OLDDEB" >/tmp/old-install.log 2>&1
eq "20261104.3 installs" "$?" 0
eq "installed" "$(dpkg-query -W -f='${Version}' sparky-stereo-apt)" "20261104.3~sparky9~0+lc1"
check "the block file is there" test -f $BLOCK
# 3. the block refuses a plain http:// source (its only use: the name cannot be resolved, nothing leaves the container)
printf 'deb http://deb.debian.org/debian unstable main\n' >/etc/apt/sources.list.d/person-plain.list
apt-get --error-on=any update >/tmp/update-blocked.log 2>&1
eq "20261104.3: apt-get --error-on=any update with a plain http source exits" "$?" 100
check "20261104.3: the error names the blocked proxy" grep -q plain-http-blocked-cve-2026-109518.invalid /tmp/update-blocked.log
printf '# a comment with http://example.org kept\n' >>/etc/apt/sources.list.d/person-plain.list
if [ "$MODE" = modified ]; then
	printf '// edited by the person: keep my proxy\n' >>$BLOCK
	cp $BLOCK /tmp/block-edited
fi
cp -p /etc/apt/apt.conf.d/60sparky-stereo-appstream-icons /tmp/icons.before
# 4. the upgrade, with no question (stdin is not a terminal: a conffile question would fail the run)
apt-get install -y "$NEWDEB" >/tmp/new-install.log 2>&1
eq "the upgrade exits" "$?" 0
grep -E 'sparky-stereo-apt:|conffile|dpkg-maintscript' /tmp/new-install.log
echo "installed: $(dpkg-query -W -f='${Version}' sparky-stereo-apt)  apt: $(dpkg-query -W -f='${Version}' apt)"
check "the new version is installed" dpkg --compare-versions "$(dpkg-query -W -f='${Version}' sparky-stereo-apt)" gt 20261104.3~sparky9~0+lc1
check "apt (>= 3.3.6) is installed" dpkg --compare-versions "$(dpkg-query -W -f='${Version}' apt)" ge 3.3.6
eq "the package declares apt (>= 3.3.6)" "$(dpkg-query -W -f='${Depends}' sparky-stereo-apt | tr ',' '\n' | grep -c 'apt (>= 3.3.6)')" 1
check "the block file is gone from apt.conf.d" test ! -e $BLOCK
eq "apt has no http proxy" "$(apt-config dump | grep -c 'Acquire::http::Proxy ')" 0
eq "dpkg no longer lists the block as a conffile of the package" "$(dpkg-query -W -f='${Conffiles}' sparky-stereo-apt | grep -c block-plain-http)" 0
eq "no leftover .dpkg-remove" "$(ls $BLOCK.dpkg-remove 2>/dev/null | wc -l)" 0
check "the icon setting (another conffile) is untouched" cmp /etc/apt/apt.conf.d/60sparky-stereo-appstream-icons /tmp/icons.before
case $MODE in
green | red)
	eq "unmodified: no .dpkg-bak" "$(ls $BLOCK.dpkg-bak 2>/dev/null | wc -l)" 0
	check "the postinst says the block was removed and why" grep -q "block-plain-http removed: it refused plain http:// sources until apt 3.3.6" /tmp/new-install.log
	;;
modified)
	check "the person's edited copy is kept as .dpkg-bak, byte for byte" cmp $BLOCK.dpkg-bak /tmp/block-edited
	check "the postinst says the copy was kept" grep -q "was changed by you: it is kept as $BLOCK.dpkg-bak" /tmp/new-install.log
	;;
esac
# 5. the conversion stays: the plain source the person wrote is https now, the comment kept, a backup made
eq "the plain source was converted" "$(grep -c '^deb https://deb.debian.org/debian unstable main' /etc/apt/sources.list.d/person-plain.list)" 1
eq "the comment kept as written" "$(grep -c '^# a comment with http://example.org kept' /etc/apt/sources.list.d/person-plain.list)" 1
eq "a backup of the file as it was" "$(grep -rl 'deb http://deb.debian.org/debian unstable' /var/backups/sparky-stereo-apt 2>/dev/null | wc -l)" 1
# 6. an https source works with the new apt
rm -f /etc/apt/sources.list.d/person-plain.list
apt-get --error-on=any update >/tmp/update-after.log 2>&1
eq "apt-get --error-on=any update over https exits" "$?" 0
check "it fetched Debian over https" grep -q 'https://deb.debian.org/debian testing InRelease' /tmp/update-after.log
eq "no plain http:// URL in the output" "$(grep -c 'http://' /tmp/update-after.log)" 0
# 7. a reinstall of the same version and a purge leave nothing behind
dpkg --configure -a >/dev/null 2>&1
check "nothing is left of the block after dpkg --configure -a" test ! -e $BLOCK
echo "RESULT $MODE: $FAIL failing checks"
[ "$FAIL" = 0 ]
