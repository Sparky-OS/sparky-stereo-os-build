#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16 (ORDER 614)
# Copyright 2026 under the GNU GPL3 License
# The Broadcom wl step (lib/broadcom-wl.sh) with doubles for every command that would touch the machine: the licence is
# shown before anything is installed, the installed file is the file whose licence was read, each step is checked, and each
# failure is said (ERROR line), kept in the engine and stops the rest. Run in a container; no network, no hardware.
# Usage: broadcom-wl.sh [package-dir]
set -uo pipefail
[[ -e /.dockerenv ]] || { echo 'Run in Docker only'; exit 1; }
PKG=$(cd "${1:-$(dirname "$0")/..}" && pwd)
SHARE=$PKG/lang
# shellcheck source=../lib/actions.sh
source "$PKG/lib/actions.sh"
# shellcheck source=../lib/broadcom-wl.sh
source "$PKG/lib/broadcom-wl.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi; }
has() { grep -Eq -- "$1" "$calls"; }
lacks() { ! grep -Eq -- "$1" "$calls"; }
first_line() { grep -nE -- "$1" "$calls" | head -n1 | cut -d: -f1; }

KERNEL=7.3.1-stereo3d16
VERSION_FULL=6.30.223.271-32
CARD=14e4:43a0
ADDRESS=0000:02:00.1

# a stand-in for Debian's package: the same file names, the licence marker line, a test text instead of Broadcom's
mkdir -p "$T/standin/DEBIAN" "$T/standin/usr/share/doc/broadcom-sta-dkms"
cat >"$T/standin/DEBIAN/control" <<EOF
Package: broadcom-sta-dkms
Version: $VERSION_FULL
Architecture: amd64
Maintainer: Test <test@example.invalid>
Description: stand-in for the test
EOF
printf 'TEST STAND-IN for the copyright file\nSOFTWARE LICENSE AGREEMENT\n(a test text, not Broadcom'"'"'s)\n' >"$T/standin/usr/share/doc/broadcom-sta-dkms/copyright"
dpkg-deb --build --root-owner-group "$T/standin" "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb" >/dev/null
mkdir -p "$T/nolicence/DEBIAN"
cp "$T/standin/DEBIAN/control" "$T/nolicence/DEBIAN/"
dpkg-deb --build --root-owner-group "$T/nolicence" "$T/nolicence.deb" >/dev/null

# the machine: sysfs under ROOT, the calls in a log; scenario resets everything
scenario() {
	rm -rf "$T/s"
	mkdir -p "$T/s/root/sys/devices/pci0000:00/$ADDRESS" "$T/s/root/sys/bus/pci/devices" "$T/s/root/sys/class/net" \
		"$T/s/root/lib/modules/$KERNEL/build" "$T/s/work" "$T/s/facts" "$T/s/pool" "$T/s/root/sys/firmware/efi/efivars"
	ln -s "../../../devices/pci0000:00/$ADDRESS" "$T/s/root/sys/bus/pci/devices/$ADDRESS"
	ROOT=$T/s/root WORK=$T/s/work FACTS=$T/s/facts WL_POOL=$T/s/pool WL_WAIT=1
	LOCALE_FILE=$T/s/locale
	export ROOT WORK FACTS WL_POOL WL_WAIT LOCALE_FILE
	# the writer of NetworkManager's settings (row 728b) has its own test; here only its call is written
	printf '#!/bin/sh\necho "broadcom-wl-settings $*" >>%q\n' "$T/s/calls" >"$T/s/settings"
	chmod +x "$T/s/settings"
	WL_SETTINGS=$T/s/settings
	export WL_SETTINGS
	echo 'LANG=en_US.UTF-8' >"$LOCALE_FILE"
	calls=$T/s/calls
	: >"$calls"
	: >"$WORK/errors"
	printf 'fact\tnetwork-no-kernel-driver\t%s\naction\tbroadcom-wl\n' "$CARD" >"$WORK/plan"
	printf '0000:02:00.1 Network controller [0280]: Broadcom Inc. and subsidiaries BCM4360 802.11ac Dual Band Wireless Network Adapter [14e4:43a0] (rev 03)\n' >"$FACTS/lspci"
	# the doubles' switches
	dbl_status=not-installed dkms_state=installed signed=yes sb=off mok=0 modprobe_fail= modprobe_msg='' no_iface= apt_rc=0 apt_headers_rc=0
	build_fails= download_rc=0 candidate=yes yad_answer=0 ask_file=$T/s/ask
	unset SPARKY_STEREO_HARDWARE_GUI DISPLAY WAYLAND_DISPLAY || true
	mkdir -p "$T/s/problems"
	: >"$T/s/problems/log"
}
pool_with() { # DEB: the disk's driver pool, with the index the packer would write
	cp "$1" "$WL_POOL/"
	(cd "$WL_POOL" && dpkg-scanpackages -m . >Packages 2>/dev/null)
}
sb_on() { printf '\x07\x00\x00\x00\x01' >"$ROOT/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"; }

uname() { echo "$KERNEL"; }
sleep() { :; }
dpkg-query() {
	case $* in
		*Status-Status*) echo "$dbl_status" ;;
		*Version*) echo "$VERSION_FULL" ;;
	esac
	[[ $dbl_status != not-installed ]] || return 1
}
apt-cache() {
	case $1 in
		policy) [[ $candidate == yes ]] && echo '  Candidate: 6.30.223.271-32' || echo '  Candidate: (none)' ;;
		show) echo 'Package: broadcom-sta-dkms'; echo 'Size: 1551384' ;;
	esac
}
apt-get() {
	echo "apt-get $*" >>"$calls"
	local arg
	for arg; do
		case $arg in
			download) cp "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb" . ; return "$download_rc" ;;
		esac
	done
	case " $* " in
		*" update "*) return 0 ;;
		*linux-headers-*) [[ $apt_headers_rc == 0 ]] && mkdir -p "$ROOT/lib/modules/$KERNEL/build"; return "$apt_headers_rc" ;;
		*" install "*)
			if ((apt_rc != 0)); then return "$apt_rc"; fi
			if [[ -n $build_fails ]]; then dbl_status=half-configured; return 1; fi
			dbl_status=installed ;;
	esac
}
dpkg() { echo "dpkg $*" >>"$calls"; dbl_status=installed; }
dkms() { echo "dkms $*" >>"$calls"; [[ $dkms_state == installed ]] && echo "broadcom-sta/6.30.223.271, $KERNEL, x86_64: installed" || echo "broadcom-sta/6.30.223.271, $KERNEL, x86_64: built"; }
modinfo() { echo "modinfo $*" >>"$calls"; [[ $signed == yes ]] && echo 'Sparky Test Signer'; return 0; }
mokutil() {
	echo "mokutil $*" >>"$calls"
	case $mok in
		0) echo "$2 is already enrolled" ;;
		1) echo "$2 is not enrolled"; return 1 ;;
		*) echo "EFI variables are not supported on this system"; return 1 ;;
	esac
}
modprobe() {
	echo "modprobe $*" >>"$calls"
	if [[ $1 == -r ]]; then rm -rf "$ROOT/sys/module/$2"; return 0; fi
	if [[ -n $modprobe_fail ]]; then echo "$modprobe_msg" >&2; return 1; fi
	mkdir -p "$ROOT/sys/module/wl" "$ROOT/sys/bus/pci/drivers/wl"
	ln -sfn "../../../bus/pci/drivers/wl" "$ROOT/sys/devices/pci0000:00/$ADDRESS/driver"
	[[ -n $no_iface ]] || { mkdir -p "$ROOT/sys/class/net/wlan0/wireless"; ln -sfn "../../../devices/pci0000:00/$ADDRESS" "$ROOT/sys/class/net/wlan0/device"; }
}
command() { if [[ $1 == -v && $2 == mokutil ]]; then return "${mokutil_missing:-0}"; fi; builtin command "$@"; }
sparky-stereo-problems() { echo "problems $*" >>"$T/s/problems/log"; }
yad() { echo "yad $*" >>"$calls"; return "$yad_answer"; }

# every failure: the ERROR line (with its number), kept in the engine under the one key, the rest stopped
expect_failure() { # NAME NUMBER
	local what=$1 number=$2
	check "$what: ERROR $number said" grep -q "^$number" "$WORK/errors"
	check "$what: kept in the engine as LOCAL$number under broadcom-wl" grep -Eq "^problems keep .*sparky-stereo-hardware broadcom-wl LOCAL$number( |$)" "$T/s/problems/log"
	check "$what: the repair is the tool's own" grep -q -- '--repair \["sparky-stereo-hardware","--broadcom-wl","repair"\]' "$T/s/problems/log"
	check "$what: not cleared" bash -c "! grep -q '^problems clear' '$T/s/problems/log'"
}

echo '== the plan: no card, no step'
scenario
: >"$WORK/plan"
setup_broadcom_wl yes >"$T/out" 2>&1
check 'a plan with no card changes nothing' lacks 'apt-get|dkms|modprobe'

echo '== not asked: told, nothing installed'
scenario
setup_broadcom_wl '' >"$T/out" 2>&1
check 'no option: nothing installed' lacks 'apt-get'
check 'no option: the person is told it needs their yes' grep -q 'needs your yes' "$T/out"
check 'no option: no package file was fetched' bash -c "! ls '$WORK/wl' 2>/dev/null | grep -q deb"

echo '== Not now is kept for the machine and can be undone'
scenario
setup_broadcom_wl no >"$T/out" 2>&1
check 'Not now is kept' wl_declined
check 'Not now installs nothing' lacks 'apt-get'
setup_broadcom_wl '' >"$T/out" 2>&1
check 'the next run says Not now was chosen and how to be asked again' grep -q 'Ask about the Wi-Fi driver again' "$T/out"
check 'the next run installs nothing' lacks 'apt-get'
wl_reset
check 'reset forgets Not now' bash -c '! [[ -e $ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-not-now ]]'
setup_broadcom_wl '' >"$T/out" 2>&1
check 'after reset the run asks for a yes again' grep -q 'needs your yes' "$T/out"

echo '== yes, from the disk, with the network unusable'
scenario
pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
curl() { echo "curl $*" >>"$calls"; return 1; }
setup_broadcom_wl yes >"$T/out" 2>&1; rc=$?
check 'the step succeeds' test $rc -eq 0
check 'the licence was printed before the install' bash -c "grep -n 'SOFTWARE LICENSE AGREEMENT' '$T/out' | head -1 | cut -d: -f1 | grep -q ."
check 'the package comes from the pool as the only apt source' has 'apt-get -o Dir::Etc::SourceList=.*/wl/pool.list -o Dir::Etc::SourceParts=/dev/null .* install broadcom-sta-dkms=6.30.223.271-32'
check 'the pool is the only source: no download, no curl' lacks 'apt-get download|^curl'
check 'no job cap and no recommends pulled' bash -c "grep 'install broadcom-sta-dkms' '$calls' | grep -q -- '--no-install-recommends' && ! grep -qE -- ' -j| nice' '$calls'"
check 'the licence was accepted on record' test -s "$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-accepted"
for v in 'dpkg status installed' 'dkms built and installed' 'Secure Boot is off' 'module wl is loaded' 'wireless interface wlan0'; do
	check "VERIFIED $v" grep -q "VERIFIED.*$v" "$T/out"
done
check 'the free modules are unloaded only when loaded, wl is loaded' has 'modprobe wl'
check 'the Wi-Fi settings are written once wl has the card' bash -c "[[ \$(grep -n '^broadcom-wl-settings write --reload' '$calls' | cut -d: -f1) -gt \$(grep -n 'modprobe wl' '$calls' | tail -n1 | cut -d: -f1) ]]"
check 'the problem is cleared' grep -q '^problems clear sparky-stereo-hardware broadcom-wl' "$T/s/problems/log"
check 'the card now counts as working' bash -c "[[ -n '$(wl_interface_of $ADDRESS)' && '$(wl_driver_of $ADDRESS)' == wl ]]"
unset -f curl

echo '== a card that already works is left alone'
setup_broadcom_wl yes >"$T/out" 2>&1
check 'a working wl is reported, nothing run again' grep -q 'VERIFIED Broadcom Wi-Fi: wl drives' "$T/out"
scenario
mkdir -p "$ROOT/sys/class/net/wlan0/wireless"; ln -s "../../../devices/pci0000:00/$ADDRESS" "$ROOT/sys/class/net/wlan0/device"
setup_broadcom_wl yes >"$T/out" 2>&1
check 'another driver already working: wl is not installed' lacks 'apt-get'
check 'another driver already working is said' grep -q 'already has a working driver' "$T/out"

echo '== yes, from the network: the size first, the licence from the downloaded file, that file installed'
scenario
setup_broadcom_wl yes >"$T/out" 2>&1; rc=$?
check 'the step succeeds' test $rc -eq 0
check 'the download size is said before the download' bash -c "grep -n '1.5MiB' '$T/out' | head -1 | cut -d: -f1 > '$T/n1'; grep -n 'RUN apt-get download' '$T/out' | head -1 | cut -d: -f1 > '$T/n2'; [[ \$(cat '$T/n1') -lt \$(cat '$T/n2') ]]"
check 'the downloaded file is the one installed' has "install .*/wl/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
check 'the licence came before the install' bash -c "[[ \$(grep -n 'SOFTWARE LICENSE AGREEMENT' '$T/out' | head -1 | cut -d: -f1) -lt \$(grep -n 'RUN apt-get.*install' '$T/out' | head -1 | cut -d: -f1) ]]"

echo '== ask, in a window (the licence shown, the answer decides)'
for answer in 0 1 252 7; do
	scenario
	pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
	export SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:99
	yad_answer=$answer
	setup_broadcom_wl ask >"$T/out" 2>&1; rc=$?
	case $answer in
		0) check 'Install: installed and verified' bash -c "grep -q 'VERIFIED the card' '$T/out' && grep -q 'install broadcom-sta-dkms=' '$calls'" ;;
		1) check 'Not now: nothing installed, kept' bash -c "! grep -q 'apt-get' '$calls' && [[ -s '$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-not-now' ]]" ;;
		252) check 'closed window: nothing installed, not kept as Not now, told' bash -c "! grep -q 'apt-get' '$calls' && [[ ! -e '$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-not-now' ]] && grep -q 'needs your yes' '$T/out'" ;;
		7) check 'a failed window is said, nothing installed' bash -c "grep -q '^52' '$WORK/errors' && ! grep -q 'apt-get' '$calls'" ;;
	esac
	check "window answer $answer: the window showed the licence file and the card" bash -c "grep -q 'yad --text-info.*--filename=.*wl-licence.txt' '$calls' && grep -q '14e4:43a0' '$calls'"
done
echo '== ask, on a terminal'
for answer in y n; do
	scenario
	pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
	echo "$answer" >"$T/s/tty"; WL_TTY=$T/s/tty
	setup_broadcom_wl ask >"$T/out" 2>&1
	check "terminal $answer: the agreement is printed and the question asked" grep -q 'SOFTWARE LICENSE AGREEMENT' "$T/out"
	if [[ $answer == y ]]; then check 'terminal y installs' has 'install broadcom-sta-dkms='; else check 'terminal n installs nothing' lacks 'apt-get'; fi
done
scenario
WL_TTY=$T/s/no-such-terminal
setup_broadcom_wl ask >"$T/out" 2>&1
check 'no terminal to ask on: nothing installed, told' bash -c "! grep -q 'install' '$calls' && grep -q 'needs your yes' '$T/out'"
unset WL_TTY

echo '== the failures, one by one'
scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; printf 'altered' >>"$WL_POOL/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
setup_broadcom_wl yes >"$T/out" 2>&1; rc=$?
check 'a pool file that differs from its recorded sum fails' test $rc -ne 0
expect_failure 'altered pool file' 75
check 'altered pool file: nothing installed, no network fallback' lacks 'apt-get'

scenario; cp "$T/nolicence.deb" "$T/broadcom-sta-dkms_9.9-1_amd64.deb"; pool_with "$T/broadcom-sta-dkms_9.9-1_amd64.deb"; rm -f "$T/broadcom-sta-dkms_9.9-1_amd64.deb"
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'a package with no licence in it' 73
check 'no licence: nothing installed' lacks 'apt-get.*install'

scenario; candidate=none; download_rc=0
apt-cache() { case $1 in policy) echo '  Candidate: (none)' ;; show) return 0 ;; esac; }
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'no pool and apt knows no package' 74
unset -f apt-cache
apt-cache() { case $1 in policy) echo '  Candidate: 6.30.223.271-32' ;; show) echo 'Size: 1551384' ;; esac; }

scenario; download_rc=100
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'the download fails (no network)' 74
check 'the download failure installs nothing' lacks 'install'

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; rm -rf "$ROOT/lib/modules/$KERNEL/build"; apt_headers_rc=100
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'no headers and apt cannot install them' 76
check 'no headers: the package is not installed' lacks 'install broadcom-sta-dkms'

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; rm -rf "$ROOT/lib/modules/$KERNEL/build"
setup_broadcom_wl yes >"$T/out" 2>&1
check 'no headers but installable: the headers come first, then the package' bash -c "[[ \$(grep -n 'linux-headers-$KERNEL' '$calls' | head -1 | cut -d: -f1) -lt \$(grep -n 'install broadcom-sta-dkms' '$calls' | head -1 | cut -d: -f1) ]]"

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; apt_rc=100
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'apt fails and the package is not on the machine' 77

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; build_fails=1
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'the package unpacked but dkms did not build' 78

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; dkms_state=built
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'apt succeeded but dkms status is not installed' 78
check 'the failure stops before the load' lacks 'modprobe wl'

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; sb_on; signed=no
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'Secure Boot on and the module unsigned' 79
check 'unsigned under Secure Boot: wl is never loaded' lacks 'modprobe wl'

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; sb_on; mok=1
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'Secure Boot on, signed, the key not enrolled' 80
check 'key not enrolled: wl is never loaded' lacks 'modprobe wl'

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; sb_on; mok=2
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'Secure Boot on and mokutil itself fails (no EFI variables): its own words are said, not a guess' 83
check "mokutil's own words reach the person" grep -q 'EFI variables are not supported' "$T/out"
scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; sb_on; mokutil_missing=1
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'Secure Boot on and mokutil missing: the key cannot be checked' 83
unset mokutil_missing

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; sb_on
setup_broadcom_wl yes >"$T/out" 2>&1; rc=$?
check 'Secure Boot on, signed and enrolled: succeeds' test $rc -eq 0
check 'the signature and the key are verified' grep -q 'VERIFIED Secure Boot is on, wl is signed by Sparky Test Signer and the key is enrolled' "$T/out"

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; modprobe_fail=1; modprobe_msg='modprobe: ERROR: could not insert wl: Exec format error'
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'modprobe wl fails' 81
check 'the reason modprobe gave is in the message' grep -q 'Exec format error' "$T/out"

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; modprobe_fail=1; modprobe_msg='modprobe: ERROR: could not insert wl: Key was rejected by service'
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'modprobe says the key was rejected' 80

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; no_iface=1
setup_broadcom_wl yes >"$T/out" 2>&1
expect_failure 'wl loads and no wireless interface appears' 82

scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; mkdir -p "$ROOT/sys/module/b43" "$ROOT/sys/module/bcma"
setup_broadcom_wl yes >"$T/out" 2>&1
check 'the free modules that are loaded are unloaded before wl, in Debian order' bash -c "[[ \$(grep -n 'modprobe -r b43' '$calls' | head -1 | cut -d: -f1) -lt \$(grep -n 'modprobe -r bcma' '$calls' | head -1 | cut -d: -f1) && \$(grep -n 'modprobe -r bcma' '$calls' | head -1 | cut -d: -f1) -lt \$(grep -n 'modprobe wl' '$calls' | head -1 | cut -d: -f1) ]]"
check 'modules that are not loaded are not touched' lacks 'modprobe -r (b44|ssb|brcmsmac|b43legacy)'

echo '== the repair continues what was accepted, never what was not'
scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
setup_broadcom_wl repair >"$T/out" 2>&1; rc=$?
check 'repair without an earlier yes installs nothing' lacks 'install'
check 'repair without an earlier yes fails (the kept problem stays) and says why' bash -c "[[ $rc -ne 0 ]] && grep -q 'needs your yes' '$T/out'"
setup_broadcom_wl yes >"$T/out" 2>&1
rm -rf "$ROOT/sys/module/wl" "$ROOT/sys/class/net/wlan0" "$ROOT/sys/devices/pci0000:00/$ADDRESS/driver"
: >"$calls"
setup_broadcom_wl repair >"$T/out" 2>&1
check 'package installed, wl not loaded: repair checks and loads again' bash -c "grep -q 'modprobe wl' '$calls' && ! grep -q 'install' '$calls' && grep -q 'VERIFIED the card' '$T/out'" 
scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
mkdir -p "$ROOT/var/lib/sparky-stereo-hardware"; printf 'broadcom-sta-dkms\t6.30.223.271-32\tdeadbeef\n' >"$ROOT/var/lib/sparky-stereo-hardware/broadcom-wl-accepted"
setup_broadcom_wl repair >"$T/out" 2>&1; rc=$?
check 'a licence that is not the one accepted needs a new yes, and the repair fails' bash -c "[[ $rc -ne 0 ]] && ! grep -q 'install broadcom-sta-dkms' '$calls' && grep -q 'needs your yes' '$T/out'"

echo '== the strings: ten languages, the same arguments, the dialog and an error in pt_BR and ja'
for n in $(seq 61 83); do
	counts=
	for l in en pt_BR es fr de pl ja ko zh_CN zh_TW; do
		text=$(source "$PKG/lang/$l"; v=LOCAL$n; echo "${!v:-}")
		[[ -n $text ]] || { fail "LOCAL$n missing in lang/$l"; continue; }
		counts+=" $(grep -o '%s' <<<"$text" | wc -l)"
	done
	[[ $(tr ' ' '\n' <<<"$counts" | sort -u | grep -c .) == 1 ]] || fail "LOCAL$n: different number of %s across languages ($counts)"
done
pass 'LOCAL61..83 in ten languages with the same number of arguments'
for l in en pt_BR es fr de pl ja ko zh_CN zh_TW; do
	for n in 61 $(seq 73 83); do
		a=$(source "$PKG/lang/$l"; v=LOCAL$n; echo "${!v}")
		b=$(source "$PKG/problems-lang/$l"; v=LOCAL$n; echo "${!v:-MISSING}")
		[[ $a == "$b" ]] || fail "LOCAL$n differs between lang/$l and problems-lang/$l"
	done
done
pass 'the window messages and the engine messages are the same text'
for l in pt_BR ja; do
	locale_name=$l; [[ $l == ja ]] && locale_name=ja_JP
	scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
	echo "LANG=${locale_name}.UTF-8" >"$LOCALE_FILE"; SHARE=$PKG/lang
	export SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:99; yad_answer=1
	setup_broadcom_wl ask >"$T/out" 2>&1
	check "$l: the dialog's title and framing are in the person's language" bash -c "grep -q -- \"--title=$(source "$PKG/lang/$l"; echo "$LOCAL61")\" '$calls'"
	check "$l: the card and the package source are in the framing" bash -c "grep -q '14e4:43a0' '$calls' && grep -q 'broadcom-sta-dkms' '$calls'"
	scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"; echo "LANG=${locale_name}.UTF-8" >"$LOCALE_FILE"; no_iface=1
	setup_broadcom_wl yes >"$T/out" 2>&1
	(SHARE=$PKG/lang; source "$SHARE/en"; source "$SHARE/$l"; render_errors "$WORK/errors") >"$T/err-$l"
	check "$l: the error reads in the person's language" bash -c "grep -q \"$(source "$PKG/lang/$l"; v=LOCAL82; printf '%s' "${!v}" | cut -c1-12)\" '$T/err-$l'"
done
echo '== the order of the licence and the install (the licence first)'
scenario; pool_with "$T/broadcom-sta-dkms_${VERSION_FULL}_amd64.deb"
export SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:99; yad_answer=0
setup_broadcom_wl ask >"$T/out" 2>&1
check 'the window opens before any apt install' bash -c "[[ \$(grep -n '^yad' '$calls' | head -1 | cut -d: -f1) -lt \$(grep -n 'install broadcom-sta-dkms' '$calls' | head -1 | cut -d: -f1) ]]"

echo "== $([[ $fails == 0 ]] && echo ALL PASS || echo "$fails FAILED")"
[[ $fails == 0 ]]
