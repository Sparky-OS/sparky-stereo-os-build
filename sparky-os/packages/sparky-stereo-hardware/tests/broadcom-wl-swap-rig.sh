#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23 (row 728)
# Copyright 2026 under the GNU GPL3 License
# The swap between b43 and wl and its way back with the real apt, dpkg, dkms, modinfo, modprobe configuration and problems
# engine, in a container started with --network none, as root, from an image that has dkms, the running kernel's published
# headers and sparky-stereo-problems: Debian's unmodified broadcom-sta-dkms is installed from a driver pool on "the disk"
# (dpkg-scanpackages, as the packer makes it), DKMS builds wl for the running kernel for real, and the purge removes the
# blacklist conffile for real. Only modprobe (a container cannot load a module) and the card's sysfs are doubles
# (tests/broadcom-wl-swap-doubles.sh); the double loads wl only when the real module file exists, and lets udev load b43
# after the bus only when the real configuration does not blacklist it. The saved profiles are an nmcli double (the real
# NetworkManager is proved in a QEMU guest). Usage: broadcom-wl-swap-rig.sh PACKAGE_DIR BROADCOM_STA_DKMS.deb
# shellcheck disable=SC2034  # the switches are read by the sourced doubles; SHARE by lib/actions.sh
set -uo pipefail
[[ -e /.dockerenv && $EUID == 0 ]] || { echo 'Run in Docker only, as root'; exit 1; }
PKG=$(cd "${1:?package dir}" && pwd)
DEB=$(realpath "${2:?broadcom-sta-dkms .deb}")
SHARE=$PKG/lang
# shellcheck source=../lib/actions.sh
source "$PKG/lib/actions.sh"
# shellcheck source=../lib/broadcom-wl.sh
source "$PKG/lib/broadcom-wl.sh"
# shellcheck source=broadcom-wl-swap-doubles.sh
source "$PKG/tests/broadcom-wl-swap-doubles.sh"
T=$(mktemp -d)
KERNEL=$(uname -r)
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
status() { dpkg-query -W -f '${db:Status-Status}' broadcom-sta-dkms 2>/dev/null || echo not-installed; }
blacklisted_for_real() { /usr/sbin/modprobe --showconfig | grep -qx 'blacklist b43'; }
wl_built() { swap_module_built; }
kept() { sparky-stereo-problems list --json sparky-stereo-hardware 2>/dev/null | grep -q "\"$1\""; }
on_b43() { [[ -e $ROOT/sys/class/net/wlp3s0b1 && $(wl_interface_driver wlp3s0b1) == b43 ]]; }
on_wl() { [[ -e $ROOT/sys/class/net/wlp3s0 && $(wl_interface_driver wlp3s0) == wl ]]; }
echo "== rig: kernel $KERNEL, dkms $(dpkg-query -W -f '${Version}' dkms), headers $(dpkg-query -W -f '${Version}' "linux-headers-$KERNEL"), engine $(dpkg-query -W -f '${Version}' sparky-stereo-problems), package $(dpkg-deb -f "$DEB" Package Version | tr '\n' ' ')"
echo "== the package file's sha256 $(sha256sum "$DEB" | cut -c1-64)"

scenario() {
	rm -rf "$T/s"
	mkdir -p "$T/s/root" "$T/s/work" "$T/s/facts" "$T/s/pool"
	ln -s /etc "$T/s/root/etc"; ln -s /var "$T/s/root/var"; ln -s /lib "$T/s/root/lib"
	ROOT=$T/s/root WORK=$T/s/work FACTS=$T/s/facts WL_POOL=$T/s/pool WL_WAIT=2 LOCALE_FILE=$T/s/locale
	NM_PROFILES=$T/s/profiles WL_TTY=$T/s/tty WL_KNOWN_MACHINES=/bin/false SWAP_REAL_CONFIG=1 SWAP_REAL_MODULE=1
	export ROOT WORK FACTS WL_POOL WL_WAIT LOCALE_FILE NM_PROFILES WL_TTY WL_KNOWN_MACHINES SWAP_REAL_CONFIG SWAP_REAL_MODULE
	echo 'LANG=en_US.UTF-8' >"$LOCALE_FILE"
	calls=$T/s/calls
	: >"$calls"
	: >"$WORK/errors"
	modprobe_fail='' modprobe_msg='' no_iface='' rm_fail='' b43_fails='' nm_down='' modify_fails=''
	swap_machine
	cp "$DEB" "$WL_POOL/"
	(cd "$WL_POOL" && dpkg-scanpackages -m . >Packages 2>/dev/null)
	nm_profile 11111111-aaaa Home wlp3s0b1
	sparky-stereo-problems clear --all sparky-stereo-hardware >/dev/null 2>&1 || true
	rm -rf /var/lib/sparky-stereo-hardware
}

echo '== swap: Broadcom licence, real install and DKMS build, b43 out, wl in'
scenario; echo y >"$WL_TTY"
setup_broadcom_wl_swap swap >"$T/swap.out" 2>&1; rc=$?
grep -E '^(RUN|VERIFIED|LICENCE|FREED|ERROR|NOTE)' "$T/swap.out" | grep -v 'dpkg-scanpackages' | cut -c1-220
check 'swap: the step succeeds' test $rc -eq 0
check 'swap: dpkg says installed' test "$(status)" = installed
check 'swap: dkms built and installed wl for the running kernel' bash -c "dkms status -m broadcom-sta -k $KERNEL | grep -q ': installed'"
check "swap: the module file exists, built for $KERNEL ($(find "/lib/modules/$KERNEL" -name 'wl.ko*'), vermagic $(modinfo -F vermagic "$(find "/lib/modules/$KERNEL" -name 'wl.ko*' | head -n1)" 2>/dev/null | cut -d' ' -f1))" wl_built
check 'swap: the package blacklists b43 for real (its conffile)' blacklisted_for_real
check 'swap: wl drives the card on wlp3s0' on_wl
check 'swap: the saved profile is freed and kept' bash -c "[[ -z \$(awk -F '\t' '\$1==\"11111111-aaaa\"{print \$4}' '$NM_PROFILES') ]] && grep -q \$'Home\tconnection.interface-name\twlp3s0b1\tb43\twl' /var/lib/sparky-stereo-hardware/broadcom-wl-profiles"
check 'swap: nothing kept in the engine' bash -c '! sparky-stereo-problems list --json sparky-stereo-hardware 2>/dev/null | grep -q broadcom-wl-swap'

echo '== back: a real purge, the blacklist gone, the kernel driver loaded by its alias as at the start'
echo y >"$WL_TTY"; : >"$calls"
setup_broadcom_wl_swap back >"$T/back.out" 2>&1; rc=$?
grep -E '^(RUN|VERIFIED|FREED|ERROR|NOTE)' "$T/back.out" | cut -c1-220
check 'back: the step succeeds' test $rc -eq 0
check 'back: dpkg knows no broadcom-sta-dkms (purged)' test "$(status)" = not-installed
check 'back: dkms has no broadcom-sta left' bash -c "[[ -z \$(dkms status -m broadcom-sta 2>/dev/null) ]]"
check 'back: the module file is gone' bash -c "[[ -z \$(find /lib/modules/$KERNEL -name 'wl.ko*') ]]"
check 'back: the blacklist is gone from the real configuration' bash -c '! /usr/sbin/modprobe --showconfig | grep -qx "blacklist b43"'
check 'back: b43 drives the card again on wlp3s0b1' on_b43

echo '== the trap: a removal keeps the blacklist conffile, so the kernel driver would not load at the start'
scenario
DEBIAN_FRONTEND=noninteractive apt-get -y -q --no-install-recommends install "$DEB" >"$T/trap.out" 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get -y -q remove broadcom-sta-dkms >>"$T/trap.out" 2>&1
check 'remove: dpkg keeps it as config-files' test "$(status)" = config-files
check 'remove: /etc/modprobe.d/broadcom-sta-dkms.conf is still there' test -e /etc/modprobe.d/broadcom-sta-dkms.conf
check 'remove: the real configuration still blacklists b43' blacklisted_for_real
swap_unload b43; swap_unload bcma; swap_load "$(cat "$ROOT/sys/bus/pci/devices/$SWAP_ADDRESS/modalias")"
check 'remove: the bus comes back by its alias, but b43 is not loaded by udev (blacklisted)' bash -c "[[ -d '$ROOT/sys/module/bcma' && ! -d '$ROOT/sys/module/b43' ]]"
DEBIAN_FRONTEND=noninteractive apt-get -y -q purge broadcom-sta-dkms >>"$T/trap.out" 2>&1
check 'purge: the conffile goes, and with it the blacklist' bash -c "[[ ! -e /etc/modprobe.d/broadcom-sta-dkms.conf ]] && ! /usr/sbin/modprobe --showconfig | grep -qx 'blacklist b43'"

echo '== a swap whose DKMS build fails is undone for real'
scenario; echo y >"$WL_TTY"
mv /usr/bin/make /usr/bin/make.real
printf '#!/bin/sh\necho "make stand-in: exit 2" >&2\nexit 2\n' >/usr/bin/make; chmod +x /usr/bin/make
setup_broadcom_wl_swap swap >"$T/fail.out" 2>&1; rc=$?
mv /usr/bin/make.real /usr/bin/make
grep -E '^(RUN apt|VERIFIED|ERROR|NOTE)' "$T/fail.out" | cut -c1-220
check 'build fails: the step fails' test $rc -ne 0
check 'build fails: ERROR 78 (the build) then 107 (undone) said' bash -c "grep -q '^78' '$WORK/errors' && grep -q '^107' '$WORK/errors'"
check 'build fails: the half-configured package was purged for real' test "$(status)" = not-installed
check 'build fails: no blacklist left' bash -c '! /usr/sbin/modprobe --showconfig | grep -qx "blacklist b43"'
check 'build fails: b43 still drives the card' on_b43
check 'build fails: kept in the real engine under broadcom-wl-swap' kept broadcom-wl-swap

echo '== a swap whose module load is refused is undone for real'
scenario; echo y >"$WL_TTY"; modprobe_fail=1 modprobe_msg='modprobe: ERROR: could not insert wl: Exec format error'
setup_broadcom_wl_swap swap >"$T/refused.out" 2>&1; rc=$?
grep -E '^(VERIFIED|ERROR)' "$T/refused.out" | cut -c1-220
check 'wl refused: the step fails after a real install and build' bash -c "[[ $rc -ne 0 ]] && grep -q 'VERIFIED dkms built and installed broadcom-sta' '$T/refused.out'"
check 'wl refused: ERROR 81 then 107' bash -c "grep -q '^81' '$WORK/errors' && grep -q '^107' '$WORK/errors'"
check 'wl refused: purged for real, module file gone' bash -c "[[ \$(dpkg-query -W -f '\${db:Status-Status}' broadcom-sta-dkms 2>/dev/null || echo not-installed) == not-installed ]] && [[ -z \$(find /lib/modules/$KERNEL -name 'wl.ko*') ]]"
check 'wl refused: b43 drives the card again' on_b43
check 'wl refused: the saved profile was not touched' test "$(nm_ifname 11111111-aaaa)" = wlp3s0b1

rm -rf "${T:?}"
echo "== $([[ $fails == 0 ]] && echo ALL PASS || echo "$fails FAILED")"
[[ $fails == 0 ]]
