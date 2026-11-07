#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# thermald after the metapackage stops depending on it (ORDER 43). Container, root, built package unpacked at /t/hw, a cpuinfo
# fixture mounted over /proc/cpuinfo; WANT is "intel" or "other", MARK is "auto" or "manual" (how thermald was installed).
#   docker run --rm --ulimit core=0 -e WANT=other -e MARK=auto -v CA:/run/host-ca.crt:ro -v HELPER:/run/https-only-apt.sh:ro -v DIR:/t:ro -v CPUINFO:/proc/cpuinfo:ro IMAGE sh /t/thermald-manual.sh
set -u
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive
failed=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; failed=1; }
apt-get -qq update >/dev/null && apt-get -qq install -y --no-install-recommends thermald grep >/dev/null 2>&1 || { echo "FAIL apt"; exit 1; }
cp -a /t/hw/usr/lib/sparky-stereo-hardware /usr/lib/ && S=/usr/lib/sparky-stereo-hardware/thermald-manual
STAMP=/var/lib/sparky-stereo-hardware/thermald-manual
echo "== $(grep -m1 '^vendor_id' /proc/cpuinfo), thermald installed as $MARK"
[ "$MARK" = auto ] && apt-mark auto thermald >/dev/null
here() { [ "$(dpkg-query -W -f='${db:Status-Status}' thermald 2>/dev/null)" = installed ]; }
is_auto() { [ -n "$(apt-mark showauto thermald)" ]; }
listed() { apt-get -s autoremove | grep -c '^Remv thermald'; }
echo "before: autoremove lists thermald: $(listed)"
$S check 2>&1 | sed 's/^/check: /'
$S auto 2>&1 | sed 's/^/auto: /'
case $WANT:$MARK in
intel:auto)
	here && ! is_auto && ok "Intel, automatic: kept and marked manual" || bad "Intel, automatic: not marked manual"
	[ "$(listed)" = 0 ] && ok "Intel: apt autoremove does not list it" || bad "Intel: autoremove lists it"
	[ -e $STAMP ] && ok "Intel: stamp written" || bad "Intel: no stamp" ;;
intel:manual)
	here && ! is_auto && ok "Intel, manual: untouched" || bad "Intel, manual: changed" ;;
other:auto)
	here && bad "other CPU, automatic: thermald is still installed" || ok "other CPU, automatic, needed by nobody: removed"
	[ -e /etc/default/thermald ] || ls /etc/thermald >/dev/null 2>&1 && ok "removed, not purged: configuration kept ($(ls /etc/thermald 2>/dev/null | head -n 2 | tr '\n' ' '))" || bad "configuration gone"
	[ -e $STAMP ] && ok "other CPU: stamp written" || bad "other CPU: no stamp" ;;
other:manual)
	here && ! is_auto && ok "other CPU, manual: left exactly as the person made it" || bad "other CPU, manual: changed"
	[ -e $STAMP ] && ok "stamp written (decision final)" || bad "no stamp" ;;
esac
echo "== second run"
if [ "$MARK" = auto ] && [ "$WANT" = other ]; then apt-get -qq install -y thermald >/dev/null 2>&1; apt-mark auto thermald >/dev/null; fi
if [ "$MARK" = auto ] && [ "$WANT" = intel ]; then apt-mark auto thermald >/dev/null; fi
$S check >/dev/null 2>&1; $S auto 2>&1 | sed 's/^/auto: /'
case $WANT:$MARK in
other:auto) here && is_auto && ok "second run does nothing (stamp): the person's reinstall stays" || bad "second run changed thermald" ;;
intel:auto) is_auto && ok "second run does nothing (stamp): a later 'auto' stays" || bad "second run marked it again" ;;
*) here && ok "second run does nothing" || bad "second run removed it" ;;
esac
if [ "$WANT:$MARK" = other:auto ]; then
	echo "== with a package that needs it: nothing is removed"
	rm -f $STAMP; apt-mark auto thermald >/dev/null
	printf 'Package: needs-thermald\nVersion: 1\nArchitecture: all\nMaintainer: t <t@example.org>\nDepends: thermald\nDescription: test\n' >/tmp/ctl; mkdir -p /tmp/nt/DEBIAN; cp /tmp/ctl /tmp/nt/DEBIAN/control; dpkg-deb --root-owner-group -b /tmp/nt /tmp/nt.deb >/dev/null
	apt-get -qq install -y /tmp/nt.deb >/dev/null 2>&1; apt-mark auto thermald >/dev/null
	$S auto 2>&1 | sed 's/^/auto: /'
	here && ok "a package depends on thermald: it stays" || bad "removed although needed"
fi
exit $failed
