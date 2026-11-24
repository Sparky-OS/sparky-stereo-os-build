#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23 (row 728)
# Copyright 2026 under the GNU GPL3 License
# The step for a Broadcom card that a free driver and wl both drive (setup_broadcom_wl_swap in lib/broadcom-wl.sh), with
# doubles for every command that would touch the machine (tests/broadcom-wl-swap-doubles.sh, and apt, dpkg and dkms here):
# nothing is installed unasked, the swap shows the licence first and is undone when a step fails, the way back purges the
# package, the saved profiles tied to the old name are freed and kept, and every failure is said and kept.
# Run in a container; no network, no hardware. Usage: broadcom-wl-swap.sh [package-dir]
# shellcheck disable=SC2034  # the switches are read by the sourced doubles (tests/broadcom-wl-swap-doubles.sh)
set -uo pipefail
[[ -e /.dockerenv ]] || { echo 'Run in Docker only'; exit 1; }
PKG=$(cd "${1:-$(dirname "$0")/..}" && pwd)
SHARE=$PKG/lang
# shellcheck source=../lib/actions.sh
source "$PKG/lib/actions.sh"
# shellcheck source=../lib/broadcom-wl.sh
source "$PKG/lib/broadcom-wl.sh"
# shellcheck source=broadcom-wl-swap-doubles.sh
source "$PKG/tests/broadcom-wl-swap-doubles.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
has() { grep -Eq -- "$1" "$calls"; }
lacks() { ! grep -Eq -- "$1" "$calls"; }
line_of() { grep -nE -- "$1" "$2" | head -n1 | cut -d: -f1; }
before() { local a b; a=$(line_of "$1" "$3"); b=$(line_of "$2" "$3"); [[ -n $a && -n $b && $a -lt $b ]]; }
KERNEL=7.3.4-stereo3d18
VERSION_FULL=6.30.223.271-32

# a stand-in for Debian's package: the same name, the licence marker line, a test text instead of Broadcom's
mkdir -p "$T/standin/DEBIAN" "$T/standin/usr/share/doc/broadcom-sta-dkms"
printf 'Package: broadcom-sta-dkms\nVersion: %s\nArchitecture: amd64\nMaintainer: Test <test@example.invalid>\nDescription: stand-in\n' "$VERSION_FULL" >"$T/standin/DEBIAN/control"
printf 'TEST STAND-IN for the copyright file\nSOFTWARE LICENSE AGREEMENT\n' >"$T/standin/usr/share/doc/broadcom-sta-dkms/copyright"
dpkg-deb --build --root-owner-group "$T/standin" "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb" >/dev/null
printf '#!/bin/sh\nexec python3 %s/bin/sparky-stereo-known-machines --table %s/share/known-machines.json "$@"\n' "$PKG" "$PKG" >"$T/known-machines"
chmod +x "$T/known-machines"

scenario() {
	rm -rf "$T/s"
	mkdir -p "$T/s/root/etc/modprobe.d" "$T/s/root/lib/modules/$KERNEL/build" "$T/s/work" "$T/s/facts" "$T/s/pool" "$T/s/problems"
	ROOT=$T/s/root WORK=$T/s/work FACTS=$T/s/facts WL_POOL=$T/s/pool WL_WAIT=1 LOCALE_FILE=$T/s/locale
	WL_KNOWN_MACHINES=$T/known-machines NM_PROFILES=$T/s/profiles WL_TTY=$T/s/tty
	export ROOT WORK FACTS WL_POOL WL_WAIT LOCALE_FILE WL_KNOWN_MACHINES NM_PROFILES WL_TTY
	echo 'LANG=en_US.UTF-8' >"$LOCALE_FILE"
	calls=$T/s/calls
	: >"$calls"
	: >"$WORK/errors"
	: >"$T/s/problems/log"
	dbl_status=not-installed dkms_state=installed signed=yes build_fails='' purge_fails='' apt_rc=0
	modprobe_fail='' modprobe_msg='' no_iface='' rm_fail='' b43_fails='' nm_down='' modify_fails=''
	unset SPARKY_STEREO_HARDWARE_GUI DISPLAY WAYLAND_DISPLAY SWAP_REAL_CONFIG SWAP_REAL_MODULE || true
	swap_machine
	cp "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb" "$WL_POOL/"
	(cd "$WL_POOL" && dpkg-scanpackages -m . >Packages 2>/dev/null)
	nm_profile 11111111-aaaa Home wlp3s0b1
	nm_profile 22222222-bbbb 'Cafe: 2' wlp3s0b1
	nm_profile 33333333-cccc Office ''
}
uname() { echo "$KERNEL"; }
sleep() { :; }
dpkg-query() {
	case $* in
		*Status-Status*) echo "$dbl_status" ;;
		*Version*) echo "$VERSION_FULL" ;;
	esac
	[[ $dbl_status != not-installed ]] || return 1
}
apt-cache() { case $1 in policy) echo '  Candidate: 6.30.223.271-32' ;; show) echo 'Size: 1551384' ;; esac; }
apt-get() {
	echo "apt-get $*" >>"$calls"
	case " $* " in
		*" update "*) return 0 ;;
		*" purge "*)
			[[ -z $purge_fails ]] || return 100
			dbl_status=not-installed
			rm -f "$ROOT/etc/modprobe.d/broadcom-sta-dkms.conf" ;;
		*" install "*)
			((apt_rc == 0)) || return "$apt_rc"
			printf 'blacklist b43\nblacklist bcma\nblacklist ssb\n' >"$ROOT/etc/modprobe.d/broadcom-sta-dkms.conf"
			if [[ -n $build_fails ]]; then dbl_status=half-configured; return 1; fi
			dbl_status=installed ;;
	esac
}
dpkg() { echo "dpkg $*" >>"$calls"; }
dkms() { echo "dkms $*" >>"$calls"; [[ $dkms_state == installed ]] && echo "broadcom-sta/6.30.223.271, $KERNEL, x86_64: installed" || echo "broadcom-sta/6.30.223.271, $KERNEL, x86_64: built"; }
modinfo() { echo "modinfo $*" >>"$calls"; [[ $signed == yes ]] && echo 'Sparky Test Signer'; return 0; }
mokutil() { echo "mokutil $*" >>"$calls"; echo "$2 is already enrolled"; }
sparky-stereo-problems() { echo "problems $*" >>"$T/s/problems/log"; }
yad() { echo "yad $*" >>"$calls"; return "${yad_answer:-0}"; }
kept() { grep -Eq "^problems keep .*sparky-stereo-hardware broadcom-wl-swap LOCAL$1( |$)" "$T/s/problems/log"; }
repair_is_swap() { grep -q -- '--repair \["sparky-stereo-hardware","--broadcom-wl","swap"\]' "$T/s/problems/log"; }
on_b43() { [[ -e $ROOT/sys/class/net/wlp3s0b1 && $(wl_interface_driver wlp3s0b1) == b43 ]]; }
on_wl() { [[ -e $ROOT/sys/class/net/wlp3s0 && $(wl_interface_driver wlp3s0) == wl ]]; }

echo '== not asked: the kernel driver keeps the card, nothing installed, the choice is said'
scenario
setup_broadcom_wl_swap '' >"$T/out" 2>&1
check 'no option: nothing installed or unloaded' lacks 'apt-get|modprobe'
check 'no option: the person is told b43 drives the card and how to choose wl' grep -q 'free driver b43 drives it.*Use Broadcom.s Wi-Fi driver.*--broadcom-wl swap' "$T/out"
check 'no option: b43 still drives the card' on_b43
setup_broadcom_wl_swap ask >"$T/out" 2>&1
check 'ask (the option of the other route) is not a yes for this card' lacks 'apt-get'
: >"$WORK/plan"
setup_broadcom_wl_swap swap >"$T/out" 2>&1
check 'a plan without the card changes nothing' lacks 'apt-get|modprobe'

echo '== swap, the person says no on the terminal'
scenario
echo n >"$WL_TTY"
setup_broadcom_wl_swap swap >"$T/out" 2>&1; rc=$?
check 'no: the step ends without failing' test $rc -eq 0
check 'no: the licence was shown and nothing installed' bash -c "grep -q 'SOFTWARE LICENSE AGREEMENT' '$T/out' && ! grep -q 'apt-get' '$calls'"
check 'no: b43 keeps the card' on_b43

echo '== swap, the person says yes on the terminal'
scenario
echo y >"$WL_TTY"
setup_broadcom_wl_swap swap >"$T/out" 2>&1; rc=$?
check 'the swap succeeds' test $rc -eq 0
check 'the framing names b43, the known machine and the two bound profiles' bash -c "grep -q 'works with b43' '$T/out' && grep -q 'On this computer (MacBookPro9,2)' '$T/out' && grep -q 'tied to the interface wlp3s0b1 (Home, Cafe: 2)' '$T/out'"
check 'the licence comes before the install' before 'SOFTWARE LICENSE AGREEMENT' 'RUN apt-get.*install' "$T/out"
check 'the package comes from the disk pool, unmodified, by version' has 'apt-get -o Dir::Etc::SourceList=.* install broadcom-sta-dkms=6.30.223.271-32'
check 'b43 then bcma unloaded, then wl loaded' bash -c "[[ \$(grep -n 'modprobe -r b43' '$calls' | cut -d: -f1) -lt \$(grep -n 'modprobe -r bcma' '$calls' | cut -d: -f1) && \$(grep -n 'modprobe -r bcma' '$calls' | cut -d: -f1) -lt \$(grep -n '^modprobe wl' '$calls' | cut -d: -f1) ]]"
check 'wl drives the card on wlp3s0' on_wl
check 'both bound profiles freed, the unbound one untouched' bash -c "[[ -z \$(awk -F '\t' '\$1==\"11111111-aaaa\"{print \$4}' '$NM_PROFILES') && -z \$(awk -F '\t' '\$1==\"22222222-bbbb\"{print \$4}' '$NM_PROFILES') ]] && grep -q 'FREED.*Cafe: 2.*wlp3s0b1.*wlp3s0 now' '$T/out' && ! grep -q 'modify 33333333' '$calls'"
check 'each freed profile kept with its old value and both drivers' bash -c "grep -c \$'connection.interface-name\twlp3s0b1\tb43\twl' '$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-profiles' | grep -qx 2"
check 'the swap is recorded with the modules to give back' grep -q $'14e4:4331\t0000:03:00.0\twlp3s0b1\tb43\tb43 bcma' "$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-swap"
check 'NetworkManager reloads its configuration' has 'nmcli general reload conf'
check 'the end says wl drives it and to restart once' grep -q 'wl drives the card 14e4:4331 now, with the wireless interface wlp3s0 (before: wlp3s0b1, driver b43). Restart the computer once' "$T/out"
check 'the swap key is cleared, nothing kept' bash -c "grep -q '^problems clear sparky-stereo-hardware broadcom-wl-swap' '$T/s/problems/log' && ! grep -q '^problems keep' '$T/s/problems/log'"

echo '== swap again on wl: nothing to do'
: >"$calls"
setup_broadcom_wl_swap swap >"$T/out" 2>&1
check 'already on wl: verified, nothing installed' bash -c "grep -q 'VERIFIED Broadcom Wi-Fi: wl drives 14e4:4331' '$T/out' && ! grep -q apt-get '$calls'"
setup_broadcom_wl_swap '' >"$T/out" 2>&1
check 'on wl, not asked: told how to go back' grep -q 'wl drives it, as you chose.*Back to the kernel.s Wi-Fi driver.*--broadcom-wl back' "$T/out"

echo '== the way back'
nm_profile 44444444-dddd Garden wlp3s0
echo n >"$WL_TTY"; : >"$calls"
setup_broadcom_wl_swap back >"$T/out" 2>&1
check 'back, no: nothing purged, wl stays' bash -c "! grep -q purge '$calls'" && check 'back, no: wl still drives the card' on_wl
echo y >"$WL_TTY"; : >"$calls"
setup_broadcom_wl_swap back >"$T/out" 2>&1; rc=$?
check 'back succeeds' test $rc -eq 0
check 'back: the package is purged (not removed) before wl is unloaded' bash -c "grep -q 'apt-get -y purge broadcom-sta-dkms' '$calls' && [[ \$(grep -n purge '$calls' | cut -d: -f1) -lt \$(grep -n 'modprobe -r wl' '$calls' | cut -d: -f1) ]]"
check 'back: the blacklist conffile is gone' test ! -e "$ROOT/etc/modprobe.d/broadcom-sta-dkms.conf"
check 'back: bcma loaded again, b43 drives the card on wlp3s0b1' on_b43
check 'back: the profile tied to wlp3s0 is freed and kept' bash -c "[[ -z \$(awk -F '\t' '\$1==\"44444444-dddd\"{print \$4}' '$NM_PROFILES') ]] && grep -q \$'Garden\tconnection.interface-name\twlp3s0\twl\tb43' '$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-profiles'"
check 'back: the swap record is gone' test ! -e "$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-swap"
check 'back: the end says b43 drives the card again' grep -q 'the kernel.s driver b43 drives the card 14e4:4331 again, with the wireless interface wlp3s0b1' "$T/out"
setup_broadcom_wl_swap back >"$T/out" 2>&1
check 'back again: nothing to do' grep -q 'has the card 14e4:4331 already' "$T/out"

echo '== every failure of the swap is undone and said'
undone() { # NAME NUMBER
	check "$1: ERROR $2 said and kept under broadcom-wl-swap" bash -c "grep -q '^$2' '$WORK/errors'" && check "$1: kept" kept "$2"
	check "$1: the repair is the swap again" repair_is_swap
	check "$1: undone: ERROR 107 said" grep -q '^107' "$WORK/errors"
	check "$1: undone: b43 drives the card again" on_b43
	check "$1: undone: the package and its blacklist are gone" bash -c "[[ \$(dpkg-query -W -f '\${db:Status-Status}' broadcom-sta-dkms) == not-installed && ! -e '$ROOT/etc/modprobe.d/broadcom-sta-dkms.conf' ]]"
	check "$1: undone: no profile was changed" bash -c "[[ \$(awk -F '\t' '\$1==\"11111111-aaaa\"{print \$4}' '$NM_PROFILES') == wlp3s0b1 ]]"
}
scenario; echo y >"$WL_TTY"; build_fails=1
setup_broadcom_wl_swap swap >"$T/out" 2>&1; rc=$?
check 'build fails: the step fails' test $rc -ne 0
undone 'dkms cannot build' 78
check 'build fails: b43 was never unloaded' lacks 'modprobe -r b43'
scenario; echo y >"$WL_TTY"; modprobe_fail=1 modprobe_msg='modprobe: ERROR: could not insert wl: Exec format error'
setup_broadcom_wl_swap swap >"$T/out" 2>&1
undone 'modprobe wl refused' 81
check 'wl refused: bcma then b43 loaded again, in that order' before 'modprobe bcma' 'modprobe b43$' "$calls"
scenario; echo y >"$WL_TTY"; no_iface=1
setup_broadcom_wl_swap swap >"$T/out" 2>&1
undone 'wl loads and no interface appears' 82
scenario; echo y >"$WL_TTY"; printf '\x07\x00\x00\x00\x01' >"$ROOT/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"; signed=no
setup_broadcom_wl_swap swap >"$T/out" 2>&1
undone 'Secure Boot on and wl unsigned' 79
check 'unsigned: wl was never loaded' lacks '^modprobe wl'
scenario; echo y >"$WL_TTY"; rm_fail=b43
setup_broadcom_wl_swap swap >"$T/out" 2>&1
undone 'b43 in use and cannot be unloaded' 82
scenario; echo y >"$WL_TTY"; modprobe_fail=1 modprobe_msg=refused; purge_fails=1
setup_broadcom_wl_swap swap >"$T/out" 2>&1
check 'the undo cannot purge: ERROR 109 kept, said with apt exit status' bash -c "grep -q '^109.100' '$WORK/errors'" && check 'purge failed: kept' kept 109
scenario; echo y >"$WL_TTY"; modprobe_fail=1 modprobe_msg=refused; b43_fails=1
setup_broadcom_wl_swap swap >"$T/out" 2>&1
check 'the kernel driver does not come back: ERROR 108 kept' bash -c "grep -q '^108' '$WORK/errors'" && check 'not back: kept' kept 108

echo '== the way back fails, said and kept'
scenario; echo y >"$WL_TTY"; setup_broadcom_wl_swap swap >/dev/null 2>&1
echo y >"$WL_TTY"; purge_fails=1; : >"$WORK/errors"
setup_broadcom_wl_swap back >"$T/out" 2>&1
check 'back cannot purge: 109, wl still drives the card' bash -c "grep -q '^109' '$WORK/errors'" && check 'back, purge failed: wl still on' on_wl
purge_fails=; rm_fail=wl; : >"$WORK/errors"
setup_broadcom_wl_swap back >"$T/out" 2>&1
check 'back, wl in use: 108 tells to restart' bash -c "grep -q '^108.*modprobe -r wl' '$WORK/errors'"

echo '== the saved profiles'
scenario; echo y >"$WL_TTY"; nm_down=1
setup_broadcom_wl_swap swap >"$T/out" 2>&1
check 'NetworkManager not running: said, nothing changed' bash -c "grep -q 'NetworkManager is not running, so no saved Wi-Fi network was checked for the old interface name wlp3s0b1' '$T/out' && ! grep -q 'connection modify' '$calls'"
scenario; echo y >"$WL_TTY"; modify_fails=1
setup_broadcom_wl_swap swap >"$T/out" 2>&1; rc=$?
check 'a profile that cannot be freed: the step fails, ERROR 110 kept with the command' bash -c "[[ $rc -ne 0 ]] && grep -q '^110.Home.wlp3s0b1' '$WORK/errors'" && check 'profile not freed: kept' kept 110
check 'a profile that cannot be freed: the swap itself stays' on_wl

echo '== in a window'
scenario; export SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:99; yad_answer=0
setup_broadcom_wl_swap swap >"$T/out" 2>&1
check 'window: the licence file with the framing text, buttons Not now and Install' bash -c "grep -q 'yad --text-info.*--text=Your computer.s Broadcom Wi-Fi card (14e4:4331) works with b43.*--filename=.*wl-licence.txt.*--button=Not now:1 --button=Install:0' '$calls'"
check 'window: the window comes before the install' before '^yad' 'install broadcom-sta-dkms' "$calls"
yad_answer=252; : >"$calls"
setup_broadcom_wl_swap back >"$T/out" 2>&1
check 'window, back: the text is the content, the closed window changes nothing' bash -c "grep -q 'yad --text-info.*--filename=.*wl-ask.txt.*--button=Back to the kernel.s Wi-Fi driver:0' '$calls' && ! grep -q purge '$calls'"
unset SPARKY_STEREO_HARDWARE_GUI DISPLAY

echo '== the strings: ten languages, the same arguments and placeholders, the kept ones the same text'
for n in $(seq 94 110); do
	ref=
	for l in en pt_BR es fr de pl ja ko zh_CN zh_TW; do
		text=$(source "$PKG/lang/$l"; v=LOCAL$n; echo "${!v:-}")
		[[ -n $text ]] || { fail "LOCAL$n missing in lang/$l"; continue; }
		sig="$(grep -o '%s' <<<"$text" | wc -l) $(grep -oE '@[A-Z]+@' <<<"$text" | sort -u | tr '\n' ' ')"
		[[ -z $ref ]] && ref=$sig
		[[ $sig == "$ref" ]] || fail "LOCAL$n in $l: $sig, English: $ref"
	done
done
pass 'LOCAL94..110 in ten languages with the same arguments and placeholders'
for l in en pt_BR es fr de pl ja ko zh_CN zh_TW; do
	for n in 108 109 110; do
		a=$(source "$PKG/lang/$l"; v=LOCAL$n; echo "${!v}")
		b=$(source "$PKG/problems-lang/$l"; v=LOCAL$n; echo "${!v:-MISSING}")
		[[ $a == "$b" ]] || fail "LOCAL$n differs between lang/$l and problems-lang/$l"
	done
done
pass 'the kept messages are the same text in lang and problems-lang'
for l in pt_BR ja; do
	scenario; echo "LANG=$([[ $l == ja ]] && echo ja_JP || echo pt_BR).UTF-8" >"$LOCALE_FILE"
	setup_broadcom_wl_swap '' >"$T/out" 2>&1
	check "$l: the note reads in the person's language" grep -q "$(source "$PKG/lang/$l"; printf '%s' "${LOCAL101:0:12}")" "$T/out"
done

echo "== $([[ $fails == 0 ]] && echo ALL PASS || echo "$fails FAILED")"
[[ $fails == 0 ]]
