#!/bin/sh
# dpkg-stereo when dpkg runs more than once, or twice at the same time, in a throwaway Debian container
# (root). What the A10 showed on 2026-10-17: after an apt-get upgrade, 228 projected conffiles of packages
# the upgrade did not touch were back in their package's bytes while their records still said lean, and
# verify called them "changed by the person".
#   A. a dpkg run is under way when a second dpkg is started; the second one runs its pre-invoke hook,
#      then fails on dpkg's lock and never runs its post-invoke: the conffiles must still end up lean
#   B. apt-get upgrade from a local repository in several dpkg runs, with a package whose conffiles are
#      projected but which is not upgraded
#   C. verify tells "restored, not projected" (the package's own bytes) from "changed by the person";
#      the next dpkg run and --project project such files again; a real edit is left alone
#   D. (with OLD.deb) the state the A10 was left in, made by the old version, healed by installing this one
#   E. the same as A with apt as the first run (apt keeps the frontend lock between its dpkg runs)
#   F. PackageKit's own dpkg runs (packagekitd on the container's system bus): an install through it, and
#      a second dpkg started while PackageKit's dpkg runs
# Usage: concurrent-test.sh DPKG-STEREO.deb WORKDIR [OLD.deb]
set -u
DEB=$1 W=$2 OLD=${3:-}
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$W/repo"
REPO=/srv/lean-test-repo
mk() {   # mk NAME VERSION [PRE-DEPENDS] [SLEEP]
	d=$W/build/$1-$2
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/sysctl.d" "$d/etc/xdg" "$d/usr/bin"
	cat > "$d/etc/sysctl.d/90-$1.conf" <<EOF
# $1: a setting with commentary for people.
# The kernel reads only the line below; these two lines go to the HR copy.
vm.swappiness = ${2%%.*}0
EOF
	cat > "$d/etc/xdg/$1rc" <<EOF
# $1's defaults; KConfig reads groups and keys, and these lines are commentary.
# A second line of commentary.
[General]
Mode=fast
EOF
	cat > "$d/usr/bin/$1" <<EOF
#!/bin/sh
# $1: prints its version. This comment and the next go in the lean form.
# A second line of commentary that the shell skips at every start.
echo "$1 $2"
EOF
	chmod 755 "$d/usr/bin/$1"
	printf '/etc/sysctl.d/90-%s.conf\n/etc/xdg/%src\n' "$1" "$1" > "$d/DEBIAN/conffiles"
	{
		printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\n' "$1" "$2"
		[ -n "${3:-}" ] && printf 'Pre-Depends: %s\n' "$3"
		printf 'Description: lean test package\n'
	} > "$d/DEBIAN/control"
	if [ -n "${4:-}" ]; then
		printf '#!/bin/sh\ntouch /run/%s-started\nsleep %s\n' "$1" "$4" > "$d/DEBIAN/preinst"
		chmod 755 "$d/DEBIAN/preinst"
	fi
	dpkg-deb --root-owner-group -b "$d" "$W/repo/$1_$2_all.deb" > /dev/null
}
lean() { ! grep -q 'commentary' "$1"; }
# with OLD.deb, part A runs on the old version: what it shows is the old behaviour, reported, not judged
aok() { if [ -n "$OLD" ]; then echo "OLD  $*"; else ok "$*"; fi; }
abad() { if [ -n "$OLD" ]; then echo "OLD  (fails) $*"; else bad "$*"; fi; }
mk keep 1.0
mk upa 1.0
mk upa 2.0
mk upa 3.0
mk upb 1.0
mk upb 2.0 'upa (>= 2.0)'
mk slow 1.0 '' 8
mk slowapt 1.0 '' 8
mk slowpk 1.0 '' 8
echo "== install dpkg-stereo ${OLD:+(the old one first: $(basename "$OLD"))}"
DPKG_STEREO_NO_PROJECT=1 dpkg -i "${OLD:-$DEB}" < /dev/null > "$W/install.log" 2>&1 || bad "install: $(tail -3 "$W/install.log")"
dpkg -i "$W/repo/keep_1.0_all.deb" "$W/repo/upa_1.0_all.deb" "$W/repo/upb_1.0_all.deb" < /dev/null > "$W/v1.log" 2>&1 || bad "install of the test packages"
lean /etc/sysctl.d/90-keep.conf && lean /etc/xdg/keeprc && lean /usr/bin/keep && ok "keep's conffiles and script projected" || bad "keep not projected"
dpkg-stereo --verify > "$W/verify0.log" 2>&1 && ok "verify: $(tail -1 "$W/verify0.log")" || bad "verify before: $(tail -3 "$W/verify0.log")"

echo "== A. a second dpkg while one runs: its pre-invoke runs, the lock stops it, no post-invoke"
rm -f /run/slow-started
dpkg -i "$W/repo/slow_1.0_all.deb" < /dev/null > "$W/slow.log" 2>&1 &
R=$!
i=0
while [ ! -e /run/slow-started ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
[ -e /run/slow-started ] && ok "the first dpkg run holds the lock (its preinst sleeps)" || bad "the first dpkg run did not start"
dpkg -i "$W/repo/keep_1.0_all.deb" < /dev/null > "$W/second.log" 2>&1 && bad "the second dpkg was not stopped" || ok "the second dpkg stopped: $(grep -m1 -i lock "$W/second.log")"
wait $R && ok "the first dpkg run finished" || bad "the first dpkg run: $(tail -3 "$W/slow.log")"
lean /etc/sysctl.d/90-keep.conf && lean /etc/xdg/keeprc && aok "keep's conffiles lean again after the first run" || abad "keep's conffiles stayed in their package's bytes"
dpkg-stereo --verify > "$W/verifyA.log" 2>&1
grep -q ' 0 problems' "$W/verifyA.log" && ! grep -q '^RESTORED' "$W/verifyA.log" && aok "verify: $(tail -1 "$W/verifyA.log")" || abad "verify after A: $(grep -c '^CHANGED' "$W/verifyA.log") CHANGED, $(grep -c '^RESTORED' "$W/verifyA.log") RESTORED; $(tail -1 "$W/verifyA.log")"
[ ! -s /var/lib/dpkg-stereo/error.log ] && ok "no hook errors" || bad "hook errors: $(tail -3 /var/lib/dpkg-stereo/error.log)"

if [ -n "$OLD" ]; then
	echo "== D. the old version's state healed by installing this one"
	n=$(grep -c '^CHANGED' "$W/verifyA.log")
	[ "$n" -gt 0 ] && ok "the old version reproduces the A10: $n conffiles CHANGED" || bad "the old version did not reproduce it"
	dpkg -i "$DEB" < /dev/null > "$W/upgrade.log" 2>&1 || bad "upgrade to the new version: $(tail -3 "$W/upgrade.log")"
	lean /etc/sysctl.d/90-keep.conf && lean /etc/xdg/keeprc && ok "keep's conffiles projected again by the upgrade's own run" || bad "still in their package's bytes after the upgrade"
	dpkg-stereo --verify > "$W/verifyD.log" 2>&1 && ok "verify: $(tail -1 "$W/verifyD.log")" || bad "verify after the upgrade: $(tail -3 "$W/verifyD.log")"
fi

echo "== B. apt-get upgrade from a local repository, in more than one dpkg run"
mkdir -p "$REPO"
cp "$W/repo"/up*_2.0_all.deb "$W/repo"/slowapt_1.0_all.deb "$W/repo"/slowpk_1.0_all.deb "$REPO/"
(cd "$REPO" && dpkg-scanpackages . /dev/null > Packages 2> /dev/null)
chmod -R a+rX "$REPO"
echo "deb [trusted=yes] file:$REPO ./" > /etc/apt/sources.list.d/lean-test.list
apt-get update -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/lean-test.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 > "$W/update.log" 2>&1 || bad "apt-get update: $(tail -3 "$W/update.log")"
runs0=$(grep -c ' startup ' /var/log/dpkg.log)
apt-get upgrade -y -o Dpkg::Use-Pty=0 -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/lean-test.list -o Dir::Etc::sourceparts=- < /dev/null > "$W/upgrade-apt.log" 2>&1 && ok "apt-get upgrade: $(grep -m1 'upgraded,' "$W/upgrade-apt.log")" || bad "apt-get: $(tail -5 "$W/upgrade-apt.log")"
runs=$(( $(grep -c ' startup ' /var/log/dpkg.log) - runs0 ))
[ "$runs" -ge 2 ] && ok "dpkg ran $runs times for it" || bad "dpkg ran only $runs times"
[ "$(dpkg-query -W -f '${Version}' upb)" = 2.0 ] && ok "upb is 2.0" || bad "upb not upgraded"
lean /etc/sysctl.d/90-keep.conf && lean /etc/xdg/keeprc && lean /usr/bin/keep && ok "keep (not upgraded) still lean" || bad "keep lost its projection"
lean /etc/sysctl.d/90-upb.conf && lean /usr/bin/upb && ok "upb 2.0 projected" || bad "upb 2.0 not projected"
grep -q 'vm.swappiness = 20' /etc/sysctl.d/90-upa.conf && lean /etc/sysctl.d/90-upa.conf && ok "upa's changed conffile arrived in 2.0 and is lean (pre-invoke ran under apt)" || bad "upa's conffile: $(cat /etc/sysctl.d/90-upa.conf)"
dpkg-stereo --verify > "$W/verifyB.log" 2>&1 && ok "verify: $(tail -1 "$W/verifyB.log")" || bad "verify after B: $(tail -3 "$W/verifyB.log")"

echo "== C. what verify calls a file, and what the next run does with it"
dpkg-deb --fsys-tarfile "$W/repo/keep_1.0_all.deb" | tar -xO ./etc/xdg/keeprc > /etc/xdg/keeprc
dpkg-deb --fsys-tarfile "$W/repo/keep_1.0_all.deb" | tar -xO ./usr/bin/keep > /usr/bin/keep
printf 'vm.dirty_ratio = 5\n' >> /etc/sysctl.d/90-keep.conf
cp /etc/sysctl.d/90-keep.conf "$W/edited.conf"
dpkg-stereo --verify > "$W/verifyC.log" 2>&1
cat "$W/verifyC.log"
grep -q '^RESTORED  /etc/xdg/keeprc' "$W/verifyC.log" && ok "a conffile back in its package's bytes: RESTORED" || bad "keeprc: $(grep keeprc "$W/verifyC.log")"
grep -q '^RESTORED  /usr/bin/keep' "$W/verifyC.log" && ok "a script back in its package's bytes: RESTORED" || bad "/usr/bin/keep: $(grep /usr/bin/keep "$W/verifyC.log")"
grep -q '^CHANGED   /etc/sysctl.d/90-keep.conf (changed by the person)' "$W/verifyC.log" && ok "a real edit: changed by the person" || bad "the edit: $(grep 90-keep "$W/verifyC.log")"
grep -q 'keeprc.*changed by the person\|/usr/bin/keep.*changed' "$W/verifyC.log" && bad "a file in its package's bytes called changed" || ok "nothing in its package's bytes called changed"
dpkg -i "$W/repo/upa_2.0_all.deb" < /dev/null > "$W/other.log" 2>&1 || bad "a dpkg run for another package"
lean /etc/xdg/keeprc && ok "the next dpkg run (another package) projected the conffile again" || bad "keeprc still in its package's bytes after the next dpkg run"
cmp -s /etc/sysctl.d/90-keep.conf "$W/edited.conf" && ok "the edited conffile left as the person made it" || bad "the edit was touched"
dpkg-stereo --project keep > "$W/project.log" 2>&1
lean /usr/bin/keep && ok "--project projected the script again: $(tail -1 "$W/project.log")" || bad "--project left /usr/bin/keep in its package's bytes"
cmp -s /etc/sysctl.d/90-keep.conf "$W/edited.conf" && ok "the edit still as the person made it" || bad "--project touched the edit"
[ "$(/usr/bin/keep)" = "keep 1.0" ] && ok "the script runs the same" || bad "the script: $(/usr/bin/keep)"
dpkg-stereo --verify > "$W/verifyC2.log" 2>&1
! grep -q '^RESTORED' "$W/verifyC2.log" && [ "$(grep -c '^CHANGED' "$W/verifyC2.log")" = 1 ] && ok "verify: only the person's edit: $(tail -1 "$W/verifyC2.log")" || bad "verify at the end: $(grep -v '^EDITED' "$W/verifyC2.log" | tail -4)"

second() {   # second NAME LOG: start a dpkg while the run that touches /run/NAME-started holds the lock
	i=0
	while [ ! -e "/run/$1-started" ] && [ $i -lt 1200 ]; do sleep 0.1; i=$((i + 1)); done
	[ -e "/run/$1-started" ] && ok "the first run holds the lock ($1's preinst sleeps)" || bad "$1 did not start"
	dpkg -i "$W/repo/keep_1.0_all.deb" < /dev/null > "$2" 2>&1 && bad "the second dpkg was not stopped" || ok "the second dpkg stopped: $(grep -m1 -i lock "$2")"
}
echo "== E. a second dpkg while apt's dpkg runs"
apt-get install -y -o Dpkg::Use-Pty=0 -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/lean-test.list -o Dir::Etc::sourceparts=- slowapt < /dev/null > "$W/slowapt.log" 2>&1 &
R=$!
second slowapt "$W/secondE.log"
wait $R && ok "apt's run finished" || bad "apt: $(tail -3 "$W/slowapt.log")"
lean /etc/xdg/keeprc && lean /etc/sysctl.d/90-upa.conf && ok "the projected conffiles lean after apt's run" || bad "conffiles left in their package's bytes after E"
dpkg-stereo --verify > "$W/verifyE.log" 2>&1; ! grep -q '^RESTORED' "$W/verifyE.log" && [ "$(grep -c '^CHANGED' "$W/verifyE.log")" = 1 ] && ok "verify: $(tail -1 "$W/verifyE.log")" || bad "verify after E: $(grep -v '^EDITED' "$W/verifyE.log" | tail -4)"

echo "== F. PackageKit's own dpkg runs"
cp "$W/repo/upa_3.0_all.deb" "$REPO/"
(cd "$REPO" && dpkg-scanpackages . /dev/null > Packages 2> /dev/null)
chmod -R a+rX "$REPO"
apt-get update > "$W/update-all.log" 2>&1
apt-get install -y --no-install-recommends -o Dpkg::Use-Pty=0 packagekit dbus-daemon dbus-system-bus-common < /dev/null > "$W/pk-install.log" 2>&1 && ok "PackageKit installed" || bad "PackageKit: $(tail -3 "$W/pk-install.log")"
mkdir -p /run/dbus
dbus-daemon --system --fork > /dev/null 2>&1
/usr/libexec/packagekitd > "$W/packagekitd.log" 2>&1 &
PK=$!
sleep 3
timeout 300 pkgcli -y install hello > "$W/pk-hello.log" 2>&1
[ "$(dpkg-query -W -f '${Status}' hello 2>/dev/null)" = "install ok installed" ] && ok "PackageKit installed hello (its own dpkg run)" || bad "PackageKit install: $(tail -3 "$W/pk-hello.log")"
lean /etc/xdg/keeprc && lean /etc/sysctl.d/90-upa.conf && ok "the projected conffiles lean after PackageKit's run" || bad "conffiles left in their package's bytes after PackageKit"
timeout 300 pkgcli -y update upa > "$W/pk-upa.log" 2>&1
[ "$(dpkg-query -W -f '${Version}' upa)" = 3.0 ] && ok "PackageKit upgraded upa to 3.0" || bad "PackageKit update: $(tail -3 "$W/pk-upa.log")"
grep -q 'vm.swappiness = 30' /etc/sysctl.d/90-upa.conf && lean /etc/sysctl.d/90-upa.conf && ok "upa's changed conffile arrived in 3.0 and is lean (no prompt under PackageKit)" || bad "upa's conffile after PackageKit: $(cat /etc/sysctl.d/90-upa.conf)"
ls /etc/sysctl.d/90-upa.conf.dpkg-* > /dev/null 2>&1 && bad "dpkg left $(ls /etc/sysctl.d/90-upa.conf.dpkg-*)" || ok "no .dpkg-dist or .dpkg-new"
timeout 300 pkgcli -y install slowpk > "$W/pk-slow.log" 2>&1 &
R=$!
second slowpk "$W/secondF.log"
wait $R
[ "$(dpkg-query -W -f '${Status}' slowpk 2>/dev/null)" = "install ok installed" ] && ok "PackageKit installed slowpk" || bad "PackageKit slowpk: $(tail -3 "$W/pk-slow.log")"
lean /etc/xdg/keeprc && lean /etc/sysctl.d/90-upa.conf && lean /etc/sysctl.d/90-slowpk.conf && ok "the projected conffiles lean after PackageKit's run and the stopped dpkg" || bad "conffiles left in their package's bytes after F"
kill $PK 2> /dev/null
dpkg-stereo --verify > "$W/verifyF.log" 2>&1; ! grep -q '^RESTORED' "$W/verifyF.log" && [ "$(grep -c '^CHANGED' "$W/verifyF.log")" = 1 ] && ok "verify: $(tail -1 "$W/verifyF.log")" || bad "verify after F: $(grep -v '^EDITED' "$W/verifyF.log" | tail -4)"
[ ! -s /var/lib/dpkg-stereo/error.log ] && ok "no hook errors" || bad "hook errors: $(tail -3 /var/lib/dpkg-stereo/error.log)"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
