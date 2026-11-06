#!/bin/bash
# sparky-stereo-firewall-apps' checks (ORDER 252c, J19), in a throwaway container (root, no NET_ADMIN) that has ufw,
# iptables and sparky-stereo-problems: the installed package against a profile that arrives later through a dpkg trigger.
# ufw writes /etc/ufw/user.rules and user6.rules without touching the kernel's firewall while it is off, which is what is read.
# Usage: DEB=/path/package.deb PROFILE_DEB=/path/kdeconnect.deb run.sh      (the profile is the one the kdeconnect package ships)
set -u
FAILS=0
ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
export LANG=C.UTF-8 DEBIAN_FRONTEND=noninteractive
PKG=sparky-stereo-firewall-apps
U4=/etc/ufw/user.rules U6=/etc/ufw/user6.rules STATE=/var/lib/$PKG/handled
rules4() { grep -c "dapp_KDEConnect" $U4; }
rules6() { grep -c "dapp_KDEConnect" $U6; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# a package that ships the profile, as kdeconnect does: built from the profile of the real kdeconnect package
mkdir -p "$T/profile/DEBIAN" "$T/profile/etc/ufw/applications.d"
dpkg-deb --fsys-tarfile "$PROFILE_DEB" | tar -x -C "$T/profile" ./etc/ufw/applications.d/kdeconnect
printf 'Package: profile-demo\nVersion: 1\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: d\n' > "$T/profile/DEBIAN/control"
dpkg-deb --root-owner-group -b "$T/profile" "$T/profile-demo.deb" >/dev/null
check "the real profile names ports 1714:1764 tcp and udp" grep -q 'ports=1714:1764/tcp|1714:1764/udp' "$T/profile/etc/ufw/applications.d/kdeconnect"

echo "== the package is installed first: the profile is not there yet"
dpkg -i "$DEB" >/dev/null 2>&1; rc=$?
check "package installs" [ $rc = 0 ]
check "no rule yet" sh -c "! grep -q dapp_KDEConnect $U4 2>/dev/null"
check "nothing recorded" sh -c "[ ! -s $STATE ]"

echo "== the profile arrives (dpkg trigger on /etc/ufw/applications.d)"
dpkg -i "$T/profile-demo.deb" > "$T/dpkg.out" 2>&1
check "the trigger ran the package" grep -q "$PKG" "$T/dpkg.out"
check "IPv4: 4 ranges x tcp and udp" [ "$(rules4)" = 8 ]
check "IPv6: 2 ranges x tcp and udp" [ "$(rules6)" = 4 ]
check "192.168.0.0/16 is allowed" grep -q -- "-p tcp -m multiport --dports 1714:1764 -s 192.168.0.0/16 -j ACCEPT" $U4
check "only private and link-local sources: no rule from anywhere" sh -c "! grep 'dapp_KDEConnect' $U4 | grep -v -- '-s \(10\.\|172\.16\.\|192\.168\.\|169\.254\.\)'"
check "IPv6 sources are unique-local or link-local" sh -c "! grep 'dapp_KDEConnect' $U6 | grep -v -- '-s \(fc00::/7\|fe80::/10\)'"
check "the profile is recorded as handled" grep -qx KDEConnect $STATE
check "the firewall itself stays off" grep -qx 'ENABLED=no' /etc/ufw/ufw.conf

echo "== again: no duplicate rules"
/usr/bin/$PKG; rc=$?
check "second run exit 0" [ $rc = 0 ]
check "same number of rules" sh -c "[ $(rules4) = 8 ] && [ $(rules6) = 4 ]"

echo "== the person deletes a rule in System Settings, Firewall: it stays deleted"
ufw delete allow from 192.168.0.0/16 to any app KDEConnect >/dev/null 2>&1
check "the rule is gone" sh -c "! grep -q -- '-s 192.168.0.0/16' $U4"
/usr/bin/$PKG
check "the package does not add it back" sh -c "! grep -q -- '-s 192.168.0.0/16' $U4"

echo "== a rule that cannot be added is said and kept; the repair works once the cause is gone"
rm -f $STATE; ufw delete allow from 10.0.0.0/8 to any app KDEConnect >/dev/null 2>&1
printf '#!/bin/sh\necho "ERROR: stand-in ufw refuses" >&2\nexit 7\n' > "$T/ufw-fail"; chmod +x "$T/ufw-fail"
SPARKY_STEREO_FIREWALL_APPS_UFW_REAL=ufw
cat > "$T/ufw-app" <<'EOS'
#!/bin/sh
# app info works (the profile is there), allow fails
case $1 in app) exec /usr/sbin/ufw "$@" ;; *) echo "ERROR: stand-in ufw refuses" >&2; exit 7 ;; esac
EOS
chmod +x "$T/ufw-app"
SPARKY_STEREO_FIREWALL_APPS_UFW=$T/ufw-app /usr/bin/$PKG > "$T/fail.out" 2>&1; rc=$?
check "the failing ufw: exit 1" [ $rc = 1 ]
check "not recorded as handled" sh -c "! grep -qx KDEConnect $STATE"
check "the engine keeps the problem" sh -c "sparky-stereo-problems list $PKG | grep -q KDEConnect"
check "the problem says what failed" sh -c "sparky-stereo-problems text $PKG KDEConnect | grep -q 'ended with status 7'"
check "the problem is told in German" sh -c "LANGUAGE=de LANG=de_DE.UTF-8 sparky-stereo-problems text $PKG KDEConnect | grep -q 'wurde mit Status 7 beendet'"
/usr/bin/$PKG; rc=$?
check "the repair (the same program) works once ufw works" [ $rc = 0 ]
check "the problem is cleared" sh -c "! sparky-stereo-problems list $PKG | grep -q KDEConnect"
check "recorded as handled" grep -qx KDEConnect $STATE

echo "== no IPv6 in ufw: only IPv4 ranges"
rm -f $STATE; ufw --force reset >/dev/null 2>&1; : > $U6
sed -i 's/^IPV6=yes/IPV6=no/' /etc/default/ufw
/usr/bin/$PKG
check "IPv4 rules present" [ "$(rules4)" = 8 ]
check "no IPv6 rule" sh -c "! grep -q dapp_KDEConnect $U6 2>/dev/null"
sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw

echo "== ufw is not on the system: nothing to do, and no failure"
rm -f $STATE
SPARKY_STEREO_FIREWALL_APPS_UFW=ufw-not-installed /usr/bin/$PKG; rc=$?
check "exit 0" [ $rc = 0 ]
check "nothing recorded" sh -c "[ ! -s $STATE ]"

echo "== removal: the rules stay, the engine lets go"
dpkg -r $PKG >/dev/null 2>&1
check "the rules stay (they are the person's firewall now)" sh -c "[ $(rules4) -gt 0 ]"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "all checks passed"
