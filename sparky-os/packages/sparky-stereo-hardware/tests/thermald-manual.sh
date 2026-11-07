#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# thermald stays on an Intel machine after the metapackage stops depending on it (ORDER 43). Container, root, with the
# built package unpacked at /t/hw and a cpuinfo fixture mounted over /proc/cpuinfo; WANT is "intel" or "other".
#   docker run --rm --ulimit core=0 -e WANT=intel -v CA:/run/host-ca.crt:ro -v HELPER:/run/https-only-apt.sh:ro -v DIR:/t:ro -v CPUINFO:/proc/cpuinfo:ro IMAGE sh /t/thermald-manual.sh
set -u
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive
failed=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; failed=1; }
apt-get -qq update >/dev/null && apt-get -qq install -y --no-install-recommends thermald grep >/dev/null 2>&1 || { echo "FAIL apt"; exit 1; }
cp -a /t/hw/usr/lib/sparky-stereo-hardware /usr/lib/ && S=/usr/lib/sparky-stereo-hardware/thermald-manual
echo "== $(grep -m1 '^vendor_id' /proc/cpuinfo)"
apt-mark auto thermald >/dev/null
echo "before: thermald is $(apt-mark showauto thermald | grep -q thermald && echo automatic || echo manual); autoremove lists it: $(apt-get -s autoremove | grep -c '^Remv thermald')"
# no systemd here: check must say what to run, and change nothing
out=$($S check 2>&1); echo "check: $out"
$S auto; echo "auto exit $?"
if [ "$WANT" = intel ]; then
	apt-mark showmanual thermald | grep -q thermald && ok "Intel: thermald is manual after the step" || bad "Intel: still automatic"
	[ "$(apt-get -s autoremove | grep -c '^Remv thermald')" = 0 ] && ok "Intel: apt autoremove does not list thermald" || bad "Intel: autoremove lists thermald"
	[ -e /var/lib/sparky-stereo-hardware/thermald-manual ] && ok "Intel: the stamp is written" || bad "Intel: no stamp"
	apt-mark auto thermald >/dev/null; $S check >/dev/null 2>&1; $S auto
	apt-mark showauto thermald | grep -q thermald && ok "Intel: runs once; a person's later 'auto' is kept" || bad "Intel: marked again"
else
	apt-mark showauto thermald | grep -q thermald && ok "other CPU: nothing is marked" || bad "other CPU: thermald was marked manual"
	[ ! -e /var/lib/sparky-stereo-hardware/thermald-manual ] && ok "other CPU: no stamp" || bad "other CPU: stamp written"
fi
exit $failed
