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
# wl_interface_of ADDRESS: the wireless interface of that PCI device, if there is one
wl_interface_of() {
	local net
	for net in "$ROOT"/sys/class/net/*; do
		[[ -e $net/wireless || -e $net/phy80211 ]] || continue
		[[ $(basename "$(readlink -f "$net/device" 2>/dev/null)") == "$1" ]] || continue
		basename "$net"
		return 0
	done
	return 0
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
	WL_DEB= WL_SOURCE=
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
	if ! dpkg-deb --fsys-tarfile "$1" 2>/dev/null | tar -xO "./$WL_LICENCE_FILE" >"$2" 2>/dev/null || ! grep -q 'SOFTWARE LICENSE AGREEMENT' "$2"; then
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
	log "NOTE ${text//@BUTTON@/$LOCAL66}"
}

# setup_broadcom_wl OPTION: the whole step for the cards of the plan in WORK/plan (FACTS holds lspci).
# OPTION: ask (the licence in a window, or on the terminal), yes (the person says yes: the licence is printed to the
# output, and installing means accepting it), no (Not now, kept for this machine), repair (go on with what the person
# already accepted), or empty (not asked: told, nothing installed). Returns 1 when a step failed (kept and told).
setup_broadcom_wl() {
	local option=${1:-} id address driver iface kernel pkg_status deb_version licence source_text answer=0
	local ids=() addresses=() working=true card_text accepted_version accepted_sum sum
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
			wl_note 69 "$card_text"
			return 0
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
				IFS=$'\t' read -r _ accepted_version accepted_sum <"$ROOT/$WL_STATE/broadcom-wl-accepted" || true
				if [[ ${accepted_sum:-} != "$sum" ]]; then
					wl_note 69 "$card_text"
					return 0
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
	local kernel=$1 address=$2 id=$3 version dkms_status module_key key_reason waited=0 iface out rc module unloaded=()
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
	# 4. a wireless interface of that card
	while :; do
		iface=$(wl_interface_of "$address")
		[[ -z $iface ]] || break
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
