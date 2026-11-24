#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23 (row 728)
# Copyright 2026 under the GNU GPL3 License
# Doubles for the card that two drivers drive, sourced by tests/broadcom-wl-swap.sh (with apt, dpkg and dkms doubled too) and
# tests/broadcom-wl-swap-rig.sh (with the real apt, dpkg, dkms and modinfo): a MacBookPro9,2's BCM4331 in a sysfs tree under
# ROOT, a modprobe that moves the card between b43 (on its bcma core, interface wlp3s0b1) and wl (on the PCI device,
# interface wlp3s0) the way the kernel does, and an nmcli that keeps saved profiles in a file. A container cannot load a
# module, so modprobe is the one command doubled in the rig; it reads the real modprobe configuration for the blacklist,
# and when the rig says so, the real module file for wl.

# shellcheck disable=SC2154  # calls, modprobe_msg and the switches are set by the test that sources this file
SWAP_ADDRESS=0000:03:00.0
SWAP_PCI=pci0000:00/0000:00:1c.1/$SWAP_ADDRESS

# swap_machine: the card on b43, as the kernel starts it (bcma claims the PCI device, b43 the 802.11 core), and the profiles
swap_machine() {
	local dev=$ROOT/sys/devices/$SWAP_PCI
	mkdir -p "$dev" "$ROOT/sys/bus/pci/devices" "$ROOT/sys/class/net" "$ROOT/sys/module" "$ROOT/sys/firmware/efi/efivars" \
		"$ROOT/sys/class/dmi/id" "$ROOT/sys/bus/pci/drivers" "$ROOT/sys/bus/bcma/drivers"
	ln -sfn "../../../devices/$SWAP_PCI" "$ROOT/sys/bus/pci/devices/$SWAP_ADDRESS"
	echo 0x14e4 >"$dev/vendor"
	echo 0x4331 >"$dev/device"
	echo pci:v000014E4d00004331sv0000106Bsd000000F5bc02sc80i00 >"$dev/modalias"
	echo 'MacBookPro9,2' >"$ROOT/sys/class/dmi/id/product_name"
	printf '%s Network controller [0280]: Broadcom Inc. and subsidiaries BCM4331 802.11a/b/g/n [14e4:4331] (rev 02)\n' "$SWAP_ADDRESS" >"$FACTS/lspci"
	printf 'fact\tnetwork-driver\t14e4:4331 b43/brcmsmac/brcmfmac (in our kernel) Broadcom Wi-Fi\nfact\tnetwork-two-drivers\t14e4:4331 b43/brcmsmac/brcmfmac\naction\tbroadcom-wl-swap\n' >"$WORK/plan"
	swap_load bcma
	swap_load b43
	: >"$NM_PROFILES"
	swap_settings_writer
}
# swap_settings_writer: the real writer of NetworkManager's settings for the cards wl can drive (bin/sparky-stereo-broadcom-wl-
# settings, row 728b), pointed at this sysfs tree and its own folders, with a permanent address for each name the card has
# (b43's and wl's differ on purpose: the file must follow the card even then); its calls are written. It runs once now, as
# udev runs it when the card's interface appears at the start, so b43's address is known before any swap.
swap_settings_writer() {
	local s=$ROOT/settings
	mkdir -p "$s"
	printf 'wlp3s0b1\t00:25:00:aa:bb:01\nwlp3s0\t00:25:00:aa:bb:02\n' >"$s/perm"
	: >"$s/NetworkManager"
	{
		echo '#!/bin/sh'
		printf 'echo "broadcom-wl-settings $*" >>%q\n' "$calls"
		printf 'export SPARKY_STEREO_SYSFS=%q SPARKY_STEREO_HARDWARE_DATA=%q SPARKY_STEREO_HARDWARE_STATE=%q\n' "$ROOT/sys" "$PKG/share" "$s/state"
		printf 'export SPARKY_STEREO_NM_RUN_CONF=%q SPARKY_STEREO_NM_ETC_CONF=%q SPARKY_STEREO_NETWORKMANAGER=%q\n' "$s/run" "$s/etc" "$s/NetworkManager"
		printf 'export SPARKY_STEREO_PERM_ADDRESSES=%q SPARKY_STEREO_PROBLEMS_STORE=%q\n' "$s/perm" "$s/problems"
		printf 'exec python3 %q "$@"\n' "$PKG/bin/sparky-stereo-broadcom-wl-settings"
	} >"$s/writer"
	chmod +x "$s/writer"
	WL_SETTINGS=$s/writer
	export WL_SETTINGS
	"$WL_SETTINGS" write >/dev/null 2>&1
	: >"$calls"
}
# swap_settings_specs: the device specs of the file the writer keeps in NetworkManager's per-boot folder
swap_settings_specs() { grep -h '^match-device=' "$ROOT/settings/run/sparky-stereo-broadcom-wl.conf" 2>/dev/null | sort -u | cut -d= -f2; }
# swap_settings_after PATTERN: the writer's last run comes after the last call that matches PATTERN
swap_settings_after() {
	local w p
	w=$(grep -n '^broadcom-wl-settings write --reload' "$calls" | tail -n1 | cut -d: -f1)
	p=$(grep -nE -- "$1" "$calls" | tail -n1 | cut -d: -f1)
	[[ -n $w && -n $p && $w -gt $p ]]
}
# swap_settings_follow PATTERN: the writer ran after the last call matching PATTERN, and the file matches the card by both of
# its addresses, b43's and wl's
swap_settings_follow() { swap_settings_after "$1" && [[ $(swap_settings_specs) == mac:00:25:00:aa:bb:01,mac:00:25:00:aa:bb:02 ]]; }
# swap_module_built: the real wl.ko DKMS installed for the running kernel, read from the file (a container with only the
# kernel's headers has no modules.dep, so modinfo by name finds nothing there), its vermagic naming the running kernel
swap_module_built() {
	local file
	file=$(find "/lib/modules/$(uname -r)" -name 'wl.ko*' 2>/dev/null | head -n1)
	[[ -n $file && $(modinfo -F vermagic "$file" 2>/dev/null) == "$(uname -r) "* ]]
}
# swap_blacklisted MODULE: the modprobe configuration blacklists it (the real configuration in the rig, ROOT's in the unit test)
swap_blacklisted() {
	if [[ -n ${SWAP_REAL_CONFIG:-} ]]; then
		/usr/sbin/modprobe --showconfig 2>/dev/null | grep -qx "blacklist $1"
	else
		grep -qsx "blacklist $1" "$ROOT"/etc/modprobe.d/*.conf
	fi
}
swap_load() {
	local dev=$ROOT/sys/devices/$SWAP_PCI
	case $1 in
		bcma|pci:*)
			[[ ! -d $ROOT/sys/module/wl ]] || { echo "modprobe: ERROR: could not insert 'bcma': Device or resource busy" >&2; return 1; }
			mkdir -p "$ROOT/sys/module/bcma" "$ROOT/sys/bus/pci/drivers/bcma-pci-bridge" "$dev/bcma0:1"
			ln -sfn ../../../../bus/pci/drivers/bcma-pci-bridge "$dev/driver"
			# udev loads the driver of the bus's 802.11 core by its alias, unless the configuration blacklists it
			if ! swap_blacklisted b43; then swap_load b43; fi ;;
		b43)
			[[ -d $ROOT/sys/module/bcma && -z ${b43_fails:-} ]] || { echo "modprobe: ERROR: could not insert 'b43': No such device" >&2; return 1; }
			mkdir -p "$ROOT/sys/module/b43" "$ROOT/sys/bus/bcma/drivers/b43" "$ROOT/sys/class/net/wlp3s0b1/wireless"
			ln -sfn ../../../../../../bus/bcma/drivers/b43 "$dev/bcma0:1/driver"
			ln -sfn "../../../devices/$SWAP_PCI/bcma0:1" "$ROOT/sys/class/net/wlp3s0b1/device" ;;
		wl)
			if [[ -n ${modprobe_fail:-} ]]; then echo "$modprobe_msg" >&2; return 1; fi
			if [[ -n ${SWAP_REAL_MODULE:-} ]] && ! swap_module_built; then
				echo "modprobe: FATAL: Module wl not found in directory /lib/modules/$(uname -r)" >&2
				return 1
			fi
			mkdir -p "$ROOT/sys/module/wl" "$ROOT/sys/bus/pci/drivers/wl"
			# the PCI device is free only when bcma left it
			[[ ! -d $ROOT/sys/module/bcma ]] || return 0
			ln -sfn ../../../../bus/pci/drivers/wl "$dev/driver"
			[[ -n ${no_iface:-} ]] || { mkdir -p "$ROOT/sys/class/net/wlp3s0/wireless"; ln -sfn "../../../devices/$SWAP_PCI" "$ROOT/sys/class/net/wlp3s0/device"; } ;;
		*) echo "modprobe: FATAL: Module $1 not found" >&2; return 1 ;;
	esac
}
swap_unload() {
	local dev=$ROOT/sys/devices/$SWAP_PCI
	[[ " ${rm_fail:-} " != *" $1 "* ]] || { echo "modprobe: FATAL: Module $1 is in use." >&2; return 1; }
	case $1 in
		b43) rm -rf "$ROOT/sys/module/b43" "$ROOT/sys/class/net/wlp3s0b1" "$dev/bcma0:1/driver" ;;
		bcma) [[ ! -d $ROOT/sys/module/b43 ]] || { echo 'modprobe: FATAL: Module bcma is in use.' >&2; return 1; }
			rm -rf "$ROOT/sys/module/bcma" "$dev/bcma0:1" "$dev/driver" ;;
		wl) rm -rf "$ROOT/sys/module/wl" "$ROOT/sys/class/net/wlp3s0"; [[ $(basename "$(readlink "$dev/driver" 2>/dev/null)") != wl ]] || rm -f "$dev/driver" ;;
		*) rm -rf "$ROOT/sys/module/$1" ;;
	esac
}
modprobe() {
	echo "modprobe $*" >>"$calls"
	if [[ $1 == -r ]]; then swap_unload "$2"; else swap_load "$1"; fi
}

# nmcli: saved profiles in NM_PROFILES, one per line: UUID<TAB>TYPE<TAB>NAME<TAB>INTERFACE-NAME
nmcli() {
	echo "nmcli $*" >>"$calls"
	local uuid
	case $* in
		'-t -f RUNNING general') [[ -n ${nm_down:-} ]] && echo stopped || echo running ;;
		'-t -f UUID,TYPE connection show') awk -F '\t' '{print $1 ":" $2}' "$NM_PROFILES" ;;
		'-g connection.interface-name connection show '*) uuid=${!#}; awk -F '\t' -v u="$uuid" '$1 == u {print $4}' "$NM_PROFILES" ;;
		'-g connection.id connection show '*) uuid=${!#}; awk -F '\t' -v u="$uuid" '$1 == u {n = $3; gsub(/:/, "\\:", n); print n}' "$NM_PROFILES" ;;
		'connection modify '*' connection.interface-name ')
			[[ -z ${modify_fails:-} ]] || { echo 'Error: failed to modify connection.interface-name: permission denied'; return 1; }
			uuid=$3
			awk -F '\t' -v OFS='\t' -v u="$uuid" '$1 == u {$4 = ""} {print}' "$NM_PROFILES" >"$NM_PROFILES.new" && mv "$NM_PROFILES.new" "$NM_PROFILES" ;;
		'general reload conf') return 0 ;;
		*) echo "nmcli double: unknown call: $*" >&2; return 2 ;;
	esac
}
nm_profile() { printf '%s\t802-11-wireless\t%s\t%s\n' "$1" "$2" "$3" >>"$NM_PROFILES"; }
nm_ifname() { awk -F '\t' -v u="$1" '$1 == u {print $4}' "$NM_PROFILES"; }
