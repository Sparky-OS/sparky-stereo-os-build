#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16 (ORDER 614)
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/16
# Broadcom's wl Wi-Fi driver for a card no driver of our kernel drives (the 802.11ac chips: BCM4360, BCM4352).
# Daniel, 2026-10-05: Debian's unmodified broadcom-sta-dkms goes on the ISO and is installed only for a matching card,
# with its licence shown. Debian's package is never modified, repacked or rebuilt here: the very file whose copyright
# file the person read is the file that is installed (from the driver pool on the disk when it is there, else from the
# network), and each step is checked after it is done: a step that fails stops the rest, says what failed, why and what
# to do, and is kept in the problems engine until the Wi-Fi works (Daniel, 2026-11-01: "either it works or not and the
# user must know"). Sourced by sparky-stereo-hardware after actions.sh (log, run, err, apt_install, load_strings).

WL_PACKAGE=broadcom-sta-dkms
WL_DKMS_NAME=broadcom-sta
WL_LICENCE_FILE=usr/share/doc/broadcom-sta-dkms/copyright
WL_POOL=${WL_POOL:-/usr/share/sparky-stereo/driver-debs}
WL_STATE=var/lib/sparky-stereo-hardware
WL_PROBLEM_PACKAGE=sparky-stereo-hardware
WL_PROBLEM_KEY=broadcom-wl
WL_REPAIR='["sparky-stereo-hardware","--broadcom-wl","repair"]'
# the modules that claim the chip's bus or the same chips (README.Debian of broadcom-sta-dkms and Debian's wiki page "wl":
# modprobe -r b44 b43 b43legacy ssb brcmsmac bcma; modprobe wl)
WL_FREE_MODULES=(b44 b43 b43legacy ssb brcmsmac bcma)
WL_WAIT=${WL_WAIT:-10}
# A card a free driver of our kernel drives and wl drives too (row 728): the kernel's driver stays the default and nothing
# is installed unasked; wl is the person's choice, with the way back. Its failures are kept under their own key, and the
# repair is the swap again.
WL_SWAP_KEY=broadcom-wl-swap
WL_SWAP_REPAIR='["sparky-stereo-hardware","--broadcom-wl","swap"]'
WL_SWAP_STATE=$WL_STATE/broadcom-wl-swap
# the conffile of broadcom-sta-dkms that keeps the free drivers from loading by themselves: a removal keeps it, a purge does not
WL_BLACKLIST=etc/modprobe.d/broadcom-sta-dkms.conf
# each saved Wi-Fi profile the tool freed from an interface name, with the value it had
WL_PROFILES_KEPT=$WL_STATE/broadcom-wl-profiles
WL_KNOWN_MACHINES=${WL_KNOWN_MACHINES:-/usr/bin/sparky-stereo-known-machines}

# wl_fail ID ARG...: the ERROR line (and the run's list of errors) and the same message kept in the engine; always 1
wl_fail() {
	err "$@"
	local id=$1
	shift
	if ! sparky-stereo-problems keep --repair "$WL_REPAIR" "$WL_PROBLEM_PACKAGE" "$WL_PROBLEM_KEY" "LOCAL$id" "$@" >/dev/null 2>&1; then
		log 'NOTE the problems engine could not keep this failure (sparky-stereo-problems keep failed); the ERROR line above and the log are all there is'
	fi
	return 1
}
wl_problem_clear() {
	sparky-stereo-problems clear "$WL_PROBLEM_PACKAGE" "$WL_PROBLEM_KEY" >/dev/null 2>&1 || true
}

# wl_cards PLAN: the PCI IDs of the plan's cards that no driver of our kernel drives
wl_cards() { awk -F '\t' '$1 == "fact" && $2 == "network-no-kernel-driver" {print $3}' "$1"; }
# wl_addresses ID LSPCI: the PCI addresses of the cards with that ID, from lspci -Dnn
wl_addresses() { grep -iF "[$1]" "$2" | awk '$1 ~ /^[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9a-f]$/ {print $1}'; }
wl_driver_of() {
	local link
	link=$(readlink "$ROOT/sys/bus/pci/devices/$1/driver" 2>/dev/null) || return 0
	basename "$link"
}
# wl_interface_of ADDRESS: the wireless interface of that PCI device, if there is one. wl binds the PCI device itself; b43
# and brcmsmac bind a core of the bus (bcma or ssb) under it, so the interface's device is the PCI device or below it
# (/sys/devices/.../0000:03:00.0/bcma0:1 for b43 on a BCM4331).
wl_interface_of() {
	local net dev
	for net in "$ROOT"/sys/class/net/*; do
		[[ -e $net/wireless || -e $net/phy80211 ]] || continue
		dev=$(readlink -f "$net/device" 2>/dev/null) || continue
		[[ $dev/ == */"$1"/* ]] || continue
		basename "$net"
		return 0
	done
	return 0
}
# wl_interface_driver IFACE: the kernel driver of the interface's own device (wl, b43, brcmsmac)
wl_interface_driver() {
	local link
	link=$(readlink "$ROOT/sys/class/net/$1/device/driver" 2>/dev/null) || return 0
	basename "$link"
}
wl_package_status() {
	local status
	status=$(dpkg-query -W -f '${db:Status-Status}' "$WL_PACKAGE" 2>/dev/null) || status=not-installed
	printf '%s\n' "${status:-not-installed}"
}
wl_declined() { [[ -s $ROOT/$WL_STATE/broadcom-wl-not-now ]]; }
wl_decline() {
	mkdir -p "$ROOT/$WL_STATE" || return 1
	printf '%s\t%s\n' "$*" "$(date -u +%Y-%m-%dT%H:%MZ)" >"$ROOT/$WL_STATE/broadcom-wl-not-now"
}
wl_reset() { rm -f "$ROOT/$WL_STATE/broadcom-wl-not-now"; }
wl_secure_boot() {
	local file
	for file in "$ROOT"/sys/firmware/efi/efivars/SecureBoot-*; do
		[[ -r $file ]] || continue
		[[ $(od -An -tu1 -j4 -N1 "$file" | tr -d ' ') == 1 ]] && return 0
	done
	return 1
}

# wl_fetch DIR: the package file, as WL_DEB, and where it came from, as WL_SOURCE (pool or network)
wl_fetch() {
	local dir=$1 deb want have bytes size
	local -x DEBIAN_FRONTEND=noninteractive
	WL_DEB='' WL_SOURCE='' WL_SIZE=''
	mkdir -p "$dir" || return 1
	deb=$(find "$WL_POOL" -maxdepth 1 -name "${WL_PACKAGE}_*_amd64.deb" 2>/dev/null | sort -V | tail -n1)
	if [[ -n $deb ]]; then
		# the disk's own copy must be the file the packer fetched from Debian: Broadcom's licence allows the driver only
		# complete and unmodified (clause 2.1), so the sum recorded in the pool's index is checked before anything else
		want=$(awk -v f="$(basename "$deb")" 'BEGIN {RS = ""; FS = "\n"}
			{fn = ""; sum = ""
			 for (i = 1; i <= NF; i++) {
				if ($i ~ /^Filename: /) { fn = substr($i, 11); sub(/^\.\//, "", fn) }
				if ($i ~ /^SHA256: /) sum = substr($i, 9)
			 }
			 if (fn == f) { print sum; exit }}' "$WL_POOL/Packages" 2>/dev/null) || want=
		have=$(sha256sum "$deb" | awk '{print $1}')
		if [[ -z $want || $want != "$have" ]]; then
			wl_fail 75 "$deb"
			return 1
		fi
		WL_DEB=$deb WL_SOURCE=pool
		return 0
	fi
	# not on the disk: the network, with the size said first; the package is fetched to read its licence, and the same
	# file is what is installed afterwards, if the person says yes
	if ! apt-cache policy "$WL_PACKAGE" 2>/dev/null | grep -q 'Candidate: [^(]'; then
		log "RUN apt-get update (apt does not know $WL_PACKAGE yet)"
		run apt-get update || true
	fi
	bytes=$(apt-cache show --no-all-versions "$WL_PACKAGE" 2>/dev/null | sed -n 's/^Size: //p' | head -n1)
	if [[ -z $bytes ]]; then
		wl_fail 74 "apt finds no $WL_PACKAGE in the configured repositories (non-free must be enabled)"
		return 1
	fi
	size=$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "$bytes bytes")
	log "Broadcom Wi-Fi: $WL_PACKAGE is not on this disk; about $size is downloaded to read its licence (nothing is installed yet)"
	if ! (cd "$dir" && run apt-get download "$WL_PACKAGE") >"$dir/download.log" 2>&1; then
		cat "$dir/download.log"
		wl_fail 74 "apt-get download failed: $(tail -n1 "$dir/download.log")"
		return 1
	fi
	cat "$dir/download.log"
	deb=$(find "$dir" -maxdepth 1 -name "${WL_PACKAGE}_*_amd64.deb" | sort -V | tail -n1)
	if [[ -z $deb ]]; then
		wl_fail 74 'apt-get download produced no file'
		return 1
	fi
	WL_DEB=$deb WL_SOURCE=network WL_SIZE=$size
}

# wl_licence DEB OUT: Broadcom's agreement as the package carries it (its copyright file, unchanged), into OUT
wl_licence() {
	if ! dpkg-deb --fsys-tarfile "$1" 2>/dev/null | tar -xO "./$WL_LICENCE_FILE" >"$2" 2>/dev/null || ! grep -qi 'license agreement' "$2"; then
		wl_fail 73 "$1"
		return 1
	fi
}

# wl_ask_window CARDS SOURCE_TEXT LICENCE_FILE: 0 yes, 1 Not now, 2 window closed (no answer), 3 the window failed
wl_ask_window() {
	local text=${LOCAL62//@INSTALL@/$LOCAL63} answer=0
	text=${text//@CARD@/$1}
	text=${text//@SOURCE@/$2}
	text=${text//&/&amp;}
	text=${text//</&lt;}
	yad --text-info --wrap --title="$LOCAL61" --text="$text" --filename="$3" --width=760 --height=520 \
		--button="$LOCAL64:1" --button="$LOCAL63:0" || answer=$?
	case $answer in 0) return 0 ;; 1) return 1 ;; 252) return 2 ;; *) return 3 ;; esac
}
# wl_ask_terminal CARDS SOURCE_TEXT LICENCE_FILE: the same on a terminal; 2 when there is none to ask on
wl_ask_terminal() {
	local text=${LOCAL62//@INSTALL@/$LOCAL63} tty=${WL_TTY:-/dev/tty} answer=
	text=${text//@CARD@/$1}
	text=${text//@SOURCE@/$2}
	if ! : <"$tty" 2>/dev/null; then return 2; fi
	printf '%s\n\n' "$text"
	cat "$3"
	printf '\n%s' "$LOCAL70"
	read -r answer <"$tty" || answer=
	echo
	case ${answer,,} in y|yes) return 0 ;; *) return 1 ;; esac
}

# wl_note ID ARG...: a message of the strings now loaded, as a NOTE line (nothing failed; the person is told)
wl_note() {
	local text
	load_strings
	text=$(render_message "$@")
	text=${text//@SWAP@/$LOCAL95}
	text=${text//@BACK@/$LOCAL96}
	log "NOTE ${text//@BUTTON@/$LOCAL66}"
}

# setup_broadcom_wl OPTION: the whole step for the cards of the plan in WORK/plan (FACTS holds lspci).
# OPTION: ask (the licence in a window, or on the terminal), yes (the person says yes: the licence is printed to the
# output, and installing means accepting it), no (Not now, kept for this machine), repair (go on with what the person
# already accepted), or empty (not asked: told, nothing installed). Returns 1 when a step failed (kept and told).
setup_broadcom_wl() {
	local option=${1:-} id address driver iface kernel pkg_status deb_version licence source_text answer=0
	local ids=() addresses=() working=true card_text accepted_sum sum
	while IFS= read -r id; do [[ -z $id ]] || ids+=("$id"); done < <(wl_cards "$WORK/plan")
	((${#ids[@]})) || return 0
	for id in "${ids[@]}"; do
		while IFS= read -r address; do [[ -z $address ]] || addresses+=("$id $address"); done < <(wl_addresses "$id" "$FACTS/lspci")
	done
	if ((${#addresses[@]} == 0)); then
		log "Broadcom Wi-Fi: the plan names ${ids[*]} but lspci shows no such card, so nothing is done"
		return 0
	fi
	for id in "${addresses[@]}"; do
		address=${id#* }
		driver=$(wl_driver_of "$address")
		iface=$(wl_interface_of "$address")
		if [[ -n $iface && $driver == wl ]]; then
			log "VERIFIED Broadcom Wi-Fi: wl drives ${id% *} at $address, wireless interface $iface"
		elif [[ -n $iface ]]; then
			log "Broadcom Wi-Fi: the card ${id% *} at $address already has a working driver ($driver, interface $iface); wl is not needed and is not installed"
		else
			working=false
		fi
	done
	if $working; then
		wl_problem_clear
		return 0
	fi
	card_text=$(printf '%s\n' "${addresses[@]%% *}" | sort -u | paste -sd, - | sed 's/,/, /g')
	kernel=$(uname -r)
	pkg_status=$(wl_package_status)
	WL_WORK=$WORK/wl
	if [[ $pkg_status == not-installed ]]; then
		case $option in
			no)
				wl_decline "$card_text" || { err 51 "${LOG:-the output above}"; return 1; }
				load_strings
				log "$(render_message 72 "$card_text")"
				return 0 ;;
			ask|yes|repair) ;;
			*)
				if wl_declined; then wl_note 65 "$card_text"; else wl_note 69 "$card_text"; fi
				return 0 ;;
		esac
		if [[ $option == repair && ! -s $ROOT/$WL_STATE/broadcom-wl-accepted ]]; then
			# a repair that needs the person's yes has not repaired anything: it says so and fails, so the kept problem stays
			wl_note 69 "$card_text"
			return 1
		fi
		wl_fetch "$WL_WORK" || return 1
		licence=$WORK/wl-licence.txt
		wl_licence "$WL_DEB" "$licence" || return 1
		deb_version=$(dpkg-deb -f "$WL_DEB" Version)
		sum=$(sha256sum "$licence" | cut -c1-64)
		load_strings
		if [[ $WL_SOURCE == pool ]]; then source_text=$LOCAL67; else source_text=$(render_message 68 "${WL_SIZE:-?}"); fi
		case $option in
			ask)
				if [[ ${SPARKY_STEREO_HARDWARE_GUI:-} == 1 && ( -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ) ]]; then
					wl_ask_window "$card_text" "$source_text" "$licence" || answer=$?
				else
					wl_ask_terminal "$card_text" "$source_text" "$licence" || answer=$?
				fi
				case $answer in
					0) ;;
					1) wl_decline "$card_text" || { err 51 "${LOG:-the output above}"; return 1; }
						log "$(render_message 72 "$card_text")"
						return 0 ;;
					2) wl_note 69 "$card_text"
						return 0 ;;
					*) err 52 "$answer"
						return 1 ;;
				esac ;;
			yes)
				# the person said yes without a window: the agreement is printed here, in the output and the log
				log "Broadcom Wi-Fi: $WL_PACKAGE $deb_version, its copyright file (Broadcom's agreement), unchanged:"
				cat "$licence" ;;
			repair)
				# the licence the person accepted is the one that applies; another one needs a new yes
				IFS=$'\t' read -r _ _ accepted_sum <"$ROOT/$WL_STATE/broadcom-wl-accepted" || true
				if [[ ${accepted_sum:-} != "$sum" ]]; then
					wl_note 69 "$card_text"
					return 1
				fi ;;
		esac
		log "LICENCE shown: $WL_PACKAGE $deb_version ($WL_SOURCE), copyright file sha256 $sum; accepted"
		mkdir -p "$ROOT/$WL_STATE" || return 1
		printf '%s\t%s\t%s\n' "$WL_PACKAGE" "$deb_version" "$sum" >"$ROOT/$WL_STATE/broadcom-wl-accepted"
		wl_reset
		wl_install_package "$kernel" || return 1
	elif [[ $pkg_status != installed ]]; then
		# unpacked or half-configured: the postinst's build did not finish; configure again, then check
		if ! run dpkg --configure "$WL_PACKAGE"; then
			wl_fail 78 "$kernel" "$(wl_build_log)"
			return 1
		fi
	fi
	wl_verify "$kernel" "${addresses[0]#* }" "${addresses[0]% *}"
}

# wl_build_log: dkms's make.log of the current build of the package
wl_build_log() {
	local log_file
	log_file=$(find "$ROOT/var/lib/dkms/$WL_DKMS_NAME" -maxdepth 3 -name make.log 2>/dev/null | sort | tail -n1)
	printf '%s\n' "${log_file:-/var/lib/dkms/$WL_DKMS_NAME/VERSION/build/make.log}"
}

# wl_install_package KERNEL: the package file the person read the licence of, installed with the running kernel's
# headers; every dependency apt needs comes from the same place as the file (the disk's pool, or the network)
wl_install_package() {
	local kernel=$1 headers status apt_options=() rc=0 target
	local -x DEBIAN_FRONTEND=noninteractive
	if [[ ! $kernel =~ ^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$ ]]; then
		wl_fail 76 "$kernel" "$kernel"
		return 1
	fi
	if [[ $WL_SOURCE == pool ]]; then
		# the disk is the only source: apt neither needs nor uses the network
		mkdir -p "$WL_WORK/lists/partial" || return 1
		printf 'deb [trusted=yes] file:%s ./\n' "$WL_POOL" >"$WL_WORK/pool.list"
		apt_options=(-o "Dir::Etc::SourceList=$WL_WORK/pool.list" -o "Dir::Etc::SourceParts=/dev/null" -o "Dir::State::Lists=$WL_WORK/lists")
		if run apt-get "${apt_options[@]}" update; then :; else
			wl_fail 77 "the driver pool of this disk" "$?"
			return 1
		fi
		target="$WL_PACKAGE=$(dpkg-deb -f "$WL_DEB" Version)"
	else
		target=$WL_DEB
	fi
	headers=linux-headers-$kernel
	if [[ ! -d $ROOT/lib/modules/$kernel/build ]]; then
		log "Broadcom Wi-Fi: the headers of the running kernel are not installed; installing $headers first"
		if ! run apt-get "${apt_options[@]}" -y --no-install-suggests install "$headers"; then
			wl_fail 76 "$kernel" "$kernel"
			return 1
		fi
		if [[ ! -d $ROOT/lib/modules/$kernel/build ]]; then
			wl_fail 76 "$kernel" "$kernel"
			return 1
		fi
	fi
	# no job cap, no nice: a DKMS build at install time uses every CPU (Daniel, 2026-11-02, "Never slow an update")
	if run apt-get "${apt_options[@]}" -y --no-install-recommends --no-install-suggests install "$target"; then :; else
		rc=$?
	fi
	status=$(wl_package_status)
	if ((rc != 0)); then
		case $status in
			installed) ;;
			half-configured|unpacked|half-installed)
				wl_fail 78 "$kernel" "$(wl_build_log)"
				return 1 ;;
			*) wl_fail 77 "$( [[ $WL_SOURCE == pool ]] && echo 'the driver pool of this disk' || echo 'the network' )" "$rc"
				return 1 ;;
		esac
	fi
	if [[ $status != installed ]]; then
		wl_fail 77 "$( [[ $WL_SOURCE == pool ]] && echo 'the driver pool of this disk' || echo 'the network' )" "$rc"
		return 1
	fi
	log "VERIFIED $WL_PACKAGE $(dpkg-query -W -f '${Version}' "$WL_PACKAGE") is installed (dpkg status installed), from $WL_SOURCE"
}

# wl_verify KERNEL ADDRESS ID: the checks after the install, each stopping the rest when it fails
wl_verify() {
	local kernel=$1 address=$2 id=$3 version dkms_status module_key waited=0 iface out rc module unloaded=()
	version=$(dpkg-query -W -f '${Version}' "$WL_PACKAGE" 2>/dev/null) || version=
	version=${version%-*}
	# 1. DKMS built it for the running kernel
	dkms_status=$(dkms status -m "$WL_DKMS_NAME" -v "$version" -k "$kernel" 2>&1) || true
	if ! grep -q ': installed' <<<"$dkms_status"; then
		log "dkms status: ${dkms_status:-nothing}"
		wl_fail 78 "$kernel" "$(wl_build_log)"
		[[ ! -r $(wl_build_log) ]] || tail -n 30 "$(wl_build_log)"
		return 1
	fi
	log "VERIFIED dkms built and installed $WL_DKMS_NAME/$version for the kernel $kernel"
	# 2. under Secure Boot the module is signed, with a key that is enrolled
	if wl_secure_boot; then
		module_key=$(modinfo -k "$kernel" -F signer wl 2>/dev/null) || module_key=
		if [[ -z $module_key ]]; then
			wl_fail 79 "$kernel" "$version" "$version"
			return 1
		fi
		if ! command -v mokutil >/dev/null 2>&1; then
			wl_fail 83 "$module_key" 'mokutil is not installed' "/var/lib/dkms/mok.pub"
			return 1
		fi
		rc=0
		out=$(mokutil --test-key "$ROOT/var/lib/dkms/mok.pub" 2>&1) || rc=$?
		# mokutil prints "... is already enrolled" or "... is not enrolled"; anything else is its own error, said as it is
		if ((rc == 0)) && grep -q 'already enrolled' <<<"$out"; then
			log "VERIFIED Secure Boot is on, wl is signed by $module_key and the key is enrolled"
		elif grep -q 'is not enrolled' <<<"$out"; then
			wl_fail 80 "$module_key" "mokutil: $(head -n1 <<<"$out")" "/var/lib/dkms/mok.pub"
			return 1
		else
			wl_fail 83 "$module_key" "mokutil exited $rc and said: $(head -n1 <<<"$out")" "/var/lib/dkms/mok.pub"
			return 1
		fi
	else
		log 'VERIFIED Secure Boot is off, so the module needs no signature'
	fi
	# 3. the load steps of Debian (README.Debian, the wiki): the free modules that claim the chip's bus out, wl in
	for module in "${WL_FREE_MODULES[@]}"; do
		[[ -d $ROOT/sys/module/$module ]] || continue
		if ! run modprobe -r "$module"; then
			unloaded+=("$module")
			log "NOTE $module is loaded and could not be unloaded (in use); wl may only take the card after a restart, when Debian's blacklist keeps $module out"
		fi
	done
	rc=0
	out=$(modprobe wl 2>&1) || rc=$?
	[[ -z $out ]] || echo "$out"
	if ((rc != 0)); then
		if grep -qiE 'key was rejected|required key not available|key rejected' <<<"$out"; then
			wl_fail 80 "${module_key:-wl}" "$out" "/var/lib/dkms/mok.pub"
		else
			wl_fail 81 "${out:-modprobe exited $rc}"
		fi
		return 1
	fi
	if [[ ! -d $ROOT/sys/module/wl ]]; then
		wl_fail 81 'modprobe wl exited 0 but /sys/module/wl does not exist'
		return 1
	fi
	log 'VERIFIED the module wl is loaded'
	# 4. a wireless interface of that card, driven by wl (not one a free driver still holds)
	while :; do
		iface=$(wl_interface_of "$address")
		if [[ -n $iface && $(wl_interface_driver "$iface") == wl ]]; then break; fi
		iface=
		((waited < WL_WAIT)) || break
		sleep 1
		waited=$((waited + 1))
	done
	if [[ -z $iface ]]; then
		wl_fail 82 "$id" "$WL_WAIT"
		return 1
	fi
	log "VERIFIED the card $id at $address has the wireless interface $iface"
	wl_problem_clear
	load_strings
	log "$(render_message 71 "$id" "$iface")"
}

# A card that a free driver of our kernel and wl both drive (row 728; the BCM4331 of a MacBookPro9,2 runs on b43).
# Daniel, 2026-10-14: "where two paths appear differ, make sure it's a user option then and do both". The kernel's driver
# keeps the card and nothing is installed unasked, as before; wl is offered with Broadcom's licence, and the way back is
# offered once wl has the card. Which of the two is the default is not a recorded design: today's is kept (Daniel's call).
# A swap that fails is undone (wl out, broadcom-sta-dkms purged, the kernel's driver back) and said; nothing is left half
# done (Daniel, 2026-11-01: "either it works or not and the user must know").

# wl_swap_cards PLAN: "ID FREE_DRIVERS" for each card of the plan that a free driver and wl both drive
wl_swap_cards() { awk -F '\t' '$1 == "fact" && $2 == "network-two-drivers" {print $3}' "$1"; }
# wl_swap_card PLAN LSPCI: the first such card present, "ID<TAB>ADDRESS<TAB>FREE_DRIVERS<TAB>INTERFACE<TAB>DRIVER" (the
# last two empty when no driver has an interface on it)
wl_swap_card() {
	local id free address iface
	while read -r id free; do
		[[ -n $id ]] || continue
		address=$(wl_addresses "$id" "$2" | head -n1)
		[[ -n $address ]] || continue
		iface=$(wl_interface_of "$address")
		printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$address" "$free" "$iface" "$(if [[ -n $iface ]]; then wl_interface_driver "$iface"; fi)"
		return 0
	done < <(wl_swap_cards "$1")
}
# wl_loaded_free_modules: the free modules loaded now, in the order Debian unloads them
wl_loaded_free_modules() {
	local module
	for module in "${WL_FREE_MODULES[@]}"; do [[ ! -d $ROOT/sys/module/$module ]] || echo "$module"; done
}
# wl_forget_swap: the record of a swap goes once the kernel's driver has the card again
wl_forget_swap() { rm -f -- "$ROOT/${WL_SWAP_STATE:?}"; }

# wl_machine_note ID: the known-machines table's sentence for this computer and card (a reference owned by broadcom-wl
# that names the card and a message), in the person's language; nothing when the computer is not in the table
wl_machine_note() {
	local out entry message product
	out=$("$WL_KNOWN_MACHINES" --sysfs-root "${ROOT:-}/sys" 2>/dev/null) || return 0
	product=$(cat "${ROOT:-}/sys/class/dmi/id/product_name" 2>/dev/null) || product=
	while IFS=$'\t' read -r entry message; do
		[[ $message =~ ^[0-9]+$ ]] || continue
		render_message "$message" "${product:-$entry}"
	done < <(python3 -I -c '
import json, sys
for entry in json.loads(sys.stdin.read()).get("matched", []):
    for ref in entry.get("references", []):
        if ref.get("owner") == "broadcom-wl" and ref.get("card") == sys.argv[1] and isinstance(ref.get("message"), int):
            print(entry.get("id", ""), ref["message"], sep="\t")' "$1" <<<"$out")
}

# wl_text TEXT CARD FREE MACHINE PROFILES SOURCE: a framing text with its placeholders filled in (the strings now loaded)
wl_text() {
	local t=$1
	t=${t//@CARD@/$2}
	t=${t//@FREE@/$3}
	t=${t//@MACHINE@/${4:+$4 }}
	t=${t//@PROFILES@/${5:+$5 }}
	t=${t//@SOURCE@/${6:+$6 }}
	t=${t//@INSTALL@/$LOCAL63}
	t=${t//@SWAP@/$LOCAL95}
	printf '%s' "${t//@BACK@/$LOCAL96}"
}
# wl_ask TEXT FILE YES_LABEL QUESTION: the text (and FILE, the licence, when there is one) in a window when the menu started
# the run (buttons "Not now" and YES_LABEL), else on the terminal (QUESTION, [y/N]). 0 yes, 1 no, 2 no answer (the window
# closed), 3 the window itself failed, 4 nobody to ask (no window and no terminal: the engine's repair runs that way)
wl_ask() {
	local text=$1 file=$2 yes=$3 question=$4 answer=0 tty=${WL_TTY:-/dev/tty} reply='' markup=()
	if [[ ${SPARKY_STEREO_HARDWARE_GUI:-} == 1 && ( -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ) ]]; then
		if [[ -z $file ]]; then
			# no licence to show: the text itself is the window's content
			file=$WORK/wl-ask.txt
			printf '%s\n' "$text" >"$file"
		else
			text=${text//&/&amp;}
			markup=(--text="${text//</&lt;}")
		fi
		yad --text-info --wrap --title="$LOCAL61" "${markup[@]}" --filename="$file" --width=760 --height=520 \
			--button="$LOCAL64:1" --button="$yes:0" || answer=$?
		case $answer in 0) return 0 ;; 1) return 1 ;; 252) return 2 ;; *) return 3 ;; esac
	fi
	if ! : <"$tty" 2>/dev/null; then return 4; fi
	printf '%s\n\n' "$text"
	[[ -z $file ]] || cat "$file"
	printf '\n%s' "$question"
	read -r reply <"$tty" || reply=
	echo
	case ${reply,,} in y|yes) return 0 ;; *) return 1 ;; esac
}

# wl_nm_running: NetworkManager answers on this computer
wl_nm_running() { command -v nmcli >/dev/null 2>&1 && [[ $(nmcli -t -f RUNNING general 2>/dev/null) == running ]]; }
# wl_profiles_bound IFACE: "UUID<TAB>NAME" of each saved Wi-Fi profile tied to that interface name. NetworkManager offers
# such a profile only on a device of that name (nm-settings-nmcli(5), connection.interface-name), so after a driver swap
# renames the card (b43 on a BCM4331 core is wlp3s0b1, wl on the PCI device is wlp3s0: systemd.net-naming-scheme(7),
# "bnumber: Broadcom bus (BCMA) core number") it no longer connects.
wl_profiles_bound() {
	local uuid type name
	[[ -n ${1:-} ]] && wl_nm_running || return 0
	while IFS=: read -r uuid type; do
		[[ -n $uuid && $type == 802-11-wireless ]] || continue
		[[ $(nmcli -g connection.interface-name connection show "$uuid" 2>/dev/null) == "$1" ]] || continue
		name=$(nmcli -g connection.id connection show "$uuid" 2>/dev/null)
		name=${name//\\:/:}
		printf '%s\t%s\n' "$uuid" "${name//\\\\/\\}"
	done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null)
}
# wl_free_profiles OLD NEW FROM TO: each saved Wi-Fi profile tied to the interface name OLD is freed from it (its
# connection.interface-name emptied), so it connects on NEW, the name the card has under the driver TO; each one is named,
# and its old value is kept with the date and both drivers in WL_PROFILES_KEPT. Returns 1 when one could not be freed (said
# and kept).
wl_free_profiles() {
	local old=$1 new=$2 from=$3 to=$4 uuid name out rc failed=0
	[[ -n $old && $old != "$new" ]] || return 0
	if ! wl_nm_running; then
		wl_note 106 "$old"
		return 0
	fi
	while IFS=$'\t' read -r uuid name; do
		[[ -n $uuid ]] || continue
		rc=0
		out=$(nmcli connection modify "$uuid" connection.interface-name '' 2>&1) || rc=$?
		if ((rc == 0)) && [[ -z $(nmcli -g connection.interface-name connection show "$uuid" 2>/dev/null) ]]; then
			mkdir -p "$ROOT/$WL_STATE"
			printf '%s\t%s\t%s\tconnection.interface-name\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$uuid" "$name" "$old" "$from" "$to" \
				>>"$ROOT/$WL_PROFILES_KEPT"
			load_strings
			log "FREED $(render_message 105 "$name" "$old" "$new")"
		else
			wl_fail 110 "$name" "$old" "${out:-nmcli exited $rc}" "$uuid"
			failed=1
		fi
	done < <(wl_profiles_bound "$old")
	return "$failed"
}

# wl_purge CARD: broadcom-sta-dkms removed with its configuration (its blacklist conffile goes only at a purge), checked
wl_purge() {
	local rc=0
	local -x DEBIAN_FRONTEND=noninteractive
	run apt-get -y purge "$WL_PACKAGE" || rc=$?
	if ((rc != 0)) || [[ $(wl_package_status) != not-installed || -e $ROOT/$WL_BLACKLIST ]]; then
		wl_fail 109 "$rc" "$1"
		return 1
	fi
	log "VERIFIED $WL_PACKAGE is purged: dpkg lists it no more and /$WL_BLACKLIST is gone"
}
# wl_free_driver_back ADDRESS MODULE...: the kernel's driver takes the card again: the modules that drove it before, loaded
# in the order the kernel loads them (the bus first), or, when none is known, the card's own alias as the kernel asks for
# it at the start; then a wireless interface of the card that another driver than wl drives. Prints the interface.
wl_free_driver_back() {
	local address=$1 i alias iface waited=0
	shift
	if (($#)); then
		for ((i = $#; i >= 1; i--)); do run modprobe "${!i}" >&2 || true; done
	else
		alias=$(cat "$ROOT/sys/bus/pci/devices/$address/modalias" 2>/dev/null) || alias=
		if [[ -n $alias ]]; then run modprobe "$alias" >&2 || true; fi
	fi
	while :; do
		iface=$(wl_interface_of "$address")
		if [[ -n $iface && $(wl_interface_driver "$iface") != wl ]]; then
			printf '%s\n' "$iface"
			return 0
		fi
		((waited < WL_WAIT)) || return 1
		sleep 1
		waited=$((waited + 1))
	done
}
# wl_undo ID ADDRESS MODULE...: a swap that failed is undone and said; always 1 (the swap did not happen)
wl_undo() {
	local id=$1 address=$2 iface
	shift 2
	log "Broadcom Wi-Fi: the swap to wl failed, so it is undone: wl out, $WL_PACKAGE removed with its settings, the kernel's driver back"
	if [[ -d $ROOT/sys/module/wl ]] && ! run modprobe -r wl; then log 'NOTE wl could not be unloaded now'; fi
	if [[ $(wl_package_status) != not-installed ]] && ! wl_purge "$id"; then return 1; fi
	if iface=$(wl_free_driver_back "$address" "$@"); then
		wl_forget_swap
		err 107 "$id" "$(wl_interface_driver "$iface")" "$iface"
	else
		wl_fail 108 "${*:-free}" "$id" "no wireless interface within $WL_WAIT seconds"
	fi
	return 1
}

# wl_swap ID ADDRESS FREE IFACE DRIVER: Broadcom's licence and the person's yes (the framing names the driver the card has,
# the known machine's note and the saved profiles that will be freed), then wl takes the card; undone when a step fails
wl_swap() {
	local id=$1 address=$2 free=$3 old_iface=$4 old_driver=$5 kernel answer=0 rc=0 licence sum deb_version source_text
	local text machine profiles new_iface modules=()
	kernel=$(uname -r)
	WL_WORK=$WORK/wl
	wl_fetch "$WL_WORK" || return 1
	licence=$WORK/wl-licence.txt
	wl_licence "$WL_DEB" "$licence" || return 1
	deb_version=$(dpkg-deb -f "$WL_DEB" Version)
	sum=$(sha256sum "$licence" | cut -c1-64)
	load_strings
	if [[ $WL_SOURCE == pool ]]; then source_text=$LOCAL67; else source_text=$(render_message 68 "${WL_SIZE:-?}"); fi
	machine=$(wl_machine_note "$id")
	profiles=$(wl_profiles_bound "$old_iface" | cut -f2 | paste -sd, - | sed 's/,/, /g')
	[[ -z $profiles ]] || profiles=$(render_message 98 "$old_iface" "$profiles")
	text=$(wl_text "$LOCAL94" "$id" "${old_driver:-${free%%/*}}" "$machine" "$profiles" "$source_text")
	wl_ask "$text" "$licence" "$LOCAL63" "$LOCAL70" || answer=$?
	case $answer in
		0) ;;
		1|2) wl_note 101 "$id" "${old_driver:-${free%%/*}}"
			return 0 ;;
		# a swap needs the person's yes: where nobody can be asked (the engine's repair) nothing changed, and that fails,
		# so a kept problem stays until the person chooses (as the wl route's repair without a yes)
		4) wl_note 101 "$id" "${old_driver:-${free%%/*}}"
			return 1 ;;
		*) err 52 "$answer"
			return 1 ;;
	esac
	log "LICENCE shown: $WL_PACKAGE $deb_version ($WL_SOURCE), copyright file sha256 $sum; accepted, to move the card $id from ${old_driver:-no driver} to wl"
	mkdir -p "$ROOT/$WL_STATE" || return 1
	printf '%s\t%s\t%s\n' "$WL_PACKAGE" "$deb_version" "$sum" >"$ROOT/$WL_STATE/broadcom-wl-accepted"
	mapfile -t modules < <(wl_loaded_free_modules)
	printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$address" "$old_iface" "$old_driver" "${modules[*]}" >"$ROOT/$WL_SWAP_STATE"
	if ! wl_install_package "$kernel" || ! wl_verify "$kernel" "$address" "$id"; then
		wl_undo "$id" "$address" "${modules[@]}"
		return 1
	fi
	new_iface=$(wl_interface_of "$address")
	# the defaults of /usr/lib/NetworkManager/conf.d/sparky-stereo-wl.conf apply at the next connection without a restart
	if wl_nm_running && ! run nmcli general reload conf; then log 'NOTE NetworkManager did not reload its configuration; it does at the next start'; fi
	wl_free_profiles "$old_iface" "$new_iface" "${old_driver:-none}" wl || rc=1
	load_strings
	log "$(render_message 103 "$id" "$new_iface" "${old_iface:-none}" "${old_driver:-none}")"
	return "$rc"
}

# wl_back ID ADDRESS FREE IFACE: the person's yes, then broadcom-sta-dkms purged, wl out and the kernel's driver back
wl_back() {
	local id=$1 address=$2 free=$3 old_iface=$4 answer=0 rc=0 out text profiles new_iface modules_text='' modules=() driver
	load_strings
	profiles=$(wl_profiles_bound "$old_iface" | cut -f2 | paste -sd, - | sed 's/,/, /g')
	[[ -z $profiles ]] || profiles=$(render_message 98 "$old_iface" "$profiles")
	text=$(wl_text "$LOCAL99" "$id" "${free%%/*}" "" "$profiles" "")
	wl_ask "$text" "" "$LOCAL96" "$LOCAL100" || answer=$?
	case $answer in
		0) ;;
		1|2) wl_note 102 "$id" "${free%%/*}"
			return 0 ;;
		4) wl_note 102 "$id" "${free%%/*}"
			return 1 ;;
		*) err 52 "$answer"
			return 1 ;;
	esac
	log "Broadcom Wi-Fi: back to the kernel's driver for the card $id, as you chose"
	if [[ -s $ROOT/$WL_SWAP_STATE ]]; then
		IFS=$'\t' read -r _ _ _ _ modules_text <"$ROOT/$WL_SWAP_STATE" || true
		read -r -a modules <<<"$modules_text"
	fi
	wl_purge "$id" || return 1
	if [[ -d $ROOT/sys/module/wl ]]; then
		out=$(modprobe -r wl 2>&1) || rc=$?
		[[ -z $out ]] || echo "$out"
		if ((rc != 0)); then
			wl_fail 108 "${free%%/*}" "$id" "modprobe -r wl: ${out:-exit $rc}"
			return 1
		fi
	fi
	if ! new_iface=$(wl_free_driver_back "$address" "${modules[@]}"); then
		wl_fail 108 "${free%%/*}" "$id" "no wireless interface within $WL_WAIT seconds"
		return 1
	fi
	driver=$(wl_interface_driver "$new_iface")
	log "VERIFIED the card $id has the wireless interface $new_iface, driven by $driver"
	wl_forget_swap
	wl_problem_clear
	wl_free_profiles "$old_iface" "$new_iface" wl "$driver" || rc=1
	load_strings
	log "$(render_message 104 "$driver" "$id" "$new_iface")"
	return "$rc"
}

# setup_broadcom_wl_swap OPTION: the step for a card that a free driver and wl both drive (fact network-two-drivers).
# swap: Broadcom's licence and the person's yes, then wl takes the card; back: the person's yes, then the kernel's driver
# takes it again; anything else: told which driver has the card and how to change it, and nothing is done.
# Returns 1 when a step failed (said, kept, and a failed swap undone).
setup_broadcom_wl_swap() {
	local option=${1:-} card id address free iface driver
	local WL_PROBLEM_KEY=$WL_SWAP_KEY WL_REPAIR=$WL_SWAP_REPAIR
	card=$(wl_swap_card "$WORK/plan" "$FACTS/lspci")
	[[ -n $card ]] || return 0
	IFS=$'\t' read -r id address free iface driver <<<"$card"
	case $option in
		swap)
			if [[ $driver == wl ]]; then
				log "VERIFIED Broadcom Wi-Fi: wl drives $id at $address, wireless interface $iface, as you chose"
				wl_problem_clear
				return 0
			fi
			wl_swap "$id" "$address" "$free" "$iface" "$driver" ;;
		back)
			if [[ $driver != wl && $(wl_package_status) == not-installed ]]; then
				log "Broadcom Wi-Fi: the kernel's driver ${driver:-${free%%/*}} has the card $id already; nothing to do"
				wl_problem_clear
				return 0
			fi
			wl_back "$id" "$address" "$free" "$iface" ;;
		*)
			if [[ $driver == wl ]]; then wl_note 102 "$id" "${free%%/*}"; else wl_note 101 "$id" "${driver:-${free%%/*}}"; fi ;;
	esac
}
