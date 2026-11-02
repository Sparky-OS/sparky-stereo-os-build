#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/01
# Nothing here falls back to something else on its own: a step that cannot do what it is for says what failed, why and
# what to do on an ERROR line and returns non-zero, and another path (nouveau for an NVIDIA card) is only ever the
# person's own choice (Daniel, 2026-11-01: "either it works or not and the user must know").

log() { printf '%s\n' "$*"; }

# The error messages are LOCAL29 to LOCAL54 of the language files, numbered, with %s for their arguments; @NOUVEAU@ stands
# for LOCAL29 (the choice of nouveau) and @BUTTON@ in it for LOCAL4 (the plan window's button), in the same language.
# render_message ID ARG...: message ID in the strings now loaded, its arguments put in
render_message() {
	local id=$1 v text nouveau
	shift
	v=LOCAL$id
	text=${!v:-}
	if [[ -z $text ]]; then
		printf 'message %s: %s\n' "$id" "$*"
		return 0
	fi
	nouveau=${LOCAL29:-}
	nouveau=${nouveau//@BUTTON@/${LOCAL4:-}}
	text=${text//@NOUVEAU@/$nouveau}
	# shellcheck disable=SC2059
	printf "$text\n" "$@"
}

# render_errors FILE: each error kept in FILE (its ID and arguments) in the strings now loaded, one per line
render_errors() {
	local line
	local -a parts
	[[ -s $1 ]] || return 0
	while IFS= read -r line; do
		IFS=$'\x1f' read -r -a parts <<<"$line"
		render_message "${parts[@]}"
	done <"$1"
}

# err ID ARG...: an ERROR line, in English in the output and the run's log (for support), and its ID and arguments kept in
# WORK/errors, so the end of the run shows it in the person's language
err() {
	local text
	text=$(if [[ -r ${SHARE:-}/en ]]; then source "$SHARE/en"; fi; render_message "$@")
	log "ERROR $text"
	if [[ -n ${WORK:-} && -d $WORK ]]; then
		(IFS=$'\x1f'; printf '%s\n' "$*") >>"$WORK/errors"
	fi
}

# load_strings: the window strings in the language of /etc/default/locale (Paweł's way: the whole LANG first, then the
# bare language; English otherwise), from SHARE
load_strings() {
	source "$SHARE/en"
	local locale_code
	locale_code=$(sed -nE 's/^LANG=["\x27]?([a-z]{2}_[A-Z]{2})(\.[^"\x27]*)?["\x27]?$/\1/p' "${LOCALE_FILE:-/etc/default/locale}" 2>/dev/null || true)
	case "$locale_code" in
		pl_PL) source "$SHARE/pl" ;;
		pt_BR) source "$SHARE/pt_BR" ;;
		zh_CN) source "$SHARE/zh_CN" ;;
		zh_TW) source "$SHARE/zh_TW" ;;
		fr_*) source "$SHARE/fr" ;;
		de_*) source "$SHARE/de" ;;
		ja_*) source "$SHARE/ja" ;;
		ko_*) source "$SHARE/ko" ;;
	esac
}

# plan_answer CODE: what the plan window's exit code means. yad gives the number of the button pressed (0 install, 2
# install but keep nouveau, 1 Cancel) and 252 for a closed window; any other code is the window's own failure, never an
# answer of the person's.
plan_answer() {
	case $1 in
		0) echo edition ;;
		2) echo nouveau ;;
		1|252) echo cancel ;;
		*) echo window-failed ;;
	esac
}

# finish_run LOG FAILED: the end of a run. No errors, or the list of the run's ERROR lines (WORK/errors), and the same list in a window
# when the menu started the run (SPARKY_STEREO_HARDWARE_GUI=1 and a display), before its terminal closes. Returns the
# run's exit status: 0, or 1 with errors.
finish_run() {
	if (("$2" == 0)); then
		log 'Hardware Setup finished with no errors. Firmware and driver changes may need a reboot.'
		return 0
	fi
	log 'Hardware Setup finished with errors: these steps were not done, and nothing was put in their place:'
	[[ -s $WORK/errors ]] || err 51 "${1:-}"
	(if [[ -r ${SHARE:-}/en ]]; then source "$SHARE/en"; fi; render_errors "$WORK/errors") | sed 's/^/ERROR /'
	if [[ ${SPARKY_STEREO_HARDWARE_GUI:-} == 1 && ( -n ${DISPLAY:-} || -n ${WAYLAND_DISPLAY:-} ) ]]; then
		load_strings
		{ printf '%s\n\n' "$LOCAL6"; render_errors "$WORK/errors"; } >"$WORK/errors-window"
		yad --text-info --wrap --title="$LOCAL5" --filename="$WORK/errors-window" --width=760 --height=420 --button="$LOCAL7:0" ||
			log "NOTE the window with these errors could not be shown; they are above and in $1"
	fi
	return 1
}
run() { printf 'RUN'; printf ' %q' "$@"; printf '\n'; "$@"; }
apt_install() { run env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install "$@"; }

setup_rig_driver() {
	local package=$1 kernel headers
	case "$package" in
		hid-tmff2-dkms|hid-fanatecff-dkms|new-lg4ff-dkms) ;;
		*) err 36 "$package"; return 1 ;;
	esac
	kernel=$(uname -r)
	if [[ ! $kernel =~ ^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$ ]]; then
		err 37 "$package" "$kernel"
		return 1
	fi
	headers="linux-headers-$kernel"
	if ! apt_install --simulate "$headers" "$package"; then
		err 38 "$package" "$headers"
		return 1
	fi
	if ! apt_install "$headers" "$package"; then
		err 39 "$package"
		return 1
	fi
}

sensor_modules() {
	awk '/add this to \/etc\/modules:/ {wanted=1; next}
		wanted && /#----cut here----/ {block++; next}
		wanted && block == 1 && /^[a-zA-Z0-9_-]+$/ {print}' "$1" | sort -u
}

setup_sensors() {
	local output module normalized failed=0
	output="$WORK/sensors-detect"
	if ! run sensors-detect --auto >"$output" 2>&1; then
		cat "$output"
		err 30
		return 1
	fi
	cat "$output"
	mapfile -t modules < <(sensor_modules "$output")
	if ((${#modules[@]})); then
		mkdir -p "$ROOT/etc/modules-load.d" || return 1
		printf '%s\n' "${modules[@]}" >"$ROOT/etc/modules-load.d/sparky-stereo-sensors.conf" || return 1
		for module in "${modules[@]}"; do
			grep -Fxq "$module" "$ROOT/etc/modules-load.d/sparky-stereo-sensors.conf" || return 1
			if ! run modprobe "$module"; then failed=1; continue; fi
			normalized=${module//-/_}
			if [[ -d "$ROOT/sys/module/$normalized" ]]; then
				log "VERIFIED sensor module $module persisted and loaded"
			else
				err 31 "$module"
				failed=1
			fi
		done
	else
		log 'No additional sensor modules recommended'
	fi
	if run sensors -u >"$WORK/readings" 2>&1 && grep -Eq '_input: *-?[0-9]+([.][0-9]+)?' "$WORK/readings"; then
		cat "$WORK/readings"
		log 'VERIFIED sensors returned numeric readings'
	else
		cat "$WORK/readings"
		log 'UNVERIFIED no sensor readings; hardware may not expose supported sensors'
		((${#modules[@]} == 0)) || failed=1
	fi
	return "$failed"
}

setup_creative() {
	local firmware
	for firmware in ctefx.bin ctefx-desktop.bin ctefx-r3di.bin ctspeq.bin; do
		[[ -s "$ROOT/usr/lib/firmware/updates/$firmware" ]] || { err 32 "$firmware"; return 1; }
	done
	mkdir -p "$ROOT/etc/modprobe.d" || return 1
	printf '%s\n' 'options snd_hda_intel enable_msi=1' >"$ROOT/etc/modprobe.d/sparky-stereo-creative.conf" || return 1
	log 'Creative firmware verified; snd_hda_intel enable_msi=1 applies after reboot'
}

ppd_action_enabled() {
	awk -v wanted="$1" 'BEGIN { RS=""; FS="\n" }
		{ name=0; enabled=0; for (i=1; i<=NF; i++) {
			if ($i == "Name: " wanted) name=1
			if ($i == "Enabled: True") enabled=1
		} if (name && enabled) found=1 }
		END { exit !found }' "$2"
}

setup_amdgpu() {
	local action failed=0
	if ! run powerprofilesctl list-actions >"$WORK/power-actions"; then
		err 34 "$*"
		return 1
	fi
	for action in "$@"; do
		if ! grep -Fxq "Name: $action" "$WORK/power-actions"; then
			err 35 "$action"
			failed=1
			continue
		fi
		if ! ppd_action_enabled "$action" "$WORK/power-actions"; then
			run powerprofilesctl configure-action "$action" --enable || return 1
		fi
		run powerprofilesctl list-actions >"$WORK/power-actions" || return 1
		ppd_action_enabled "$action" "$WORK/power-actions" || { err 33 "$action"; return 1; }
		log "VERIFIED PPD action $action enabled"
	done
	return "$failed"
}

setup_nvidia_runtime_pm() {
	mkdir -p "$ROOT/etc/modprobe.d" "$ROOT/etc/udev/rules.d" || return 1
	printf '%s\n' 'options nvidia NVreg_DynamicPowerManagement=0x02' >"$ROOT/etc/modprobe.d/sparky-stereo-nvidia-runtime-pm.conf" || return 1
	cat >"$ROOT/etc/udev/rules.d/80-sparky-stereo-nvidia-runtime-pm.rules" <<'EOF' || return 1
ACTION=="bind", SUBSYSTEM=="pci", DRIVER=="nvidia", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="bind", SUBSYSTEM=="pci", DRIVER=="nvidia", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="auto"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030000", TEST=="power/control", ATTR{power/control}="on"
ACTION=="unbind", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x030200", TEST=="power/control", ATTR{power/control}="on"
EOF
	log 'NVIDIA laptop runtime PM configured for next driver bind/reboot; actual RTD3 support is hardware-dependent'
}

# Files of apt's sources, other than the one sparky-stereo-cuda-repo ships, that name NVIDIA's CUDA repository (outside a
# comment): a repository the person set up themselves, such as NVIDIA's own cuda-keyring.
cuda_sources_elsewhere() {
	local file own="$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
	local -a found=()
	for file in "$ROOT/etc/apt/sources.list" "$ROOT"/etc/apt/sources.list.d/*.list "$ROOT"/etc/apt/sources.list.d/*.sources; do
		[[ -f $file && $file != "$own" ]] || continue
		if sed 's/#.*//' "$file" | grep -Fq "$1"; then found+=("${file#"$ROOT"}"); fi
	done
	printf '%s\n' "${found[*]}"
}

package_installed() {
	[[ $(dpkg-query -W -f '${db:Status-Abbrev}' "$1" 2>/dev/null) == ii* ]]
}

# nvidia_version_of MODULE_VERSION: NVIDIA's driver version the edition's module is built for, the module's version
# without our +stereo3d suffix and Lean Code's +lc mark after it (615.71.09-2+stereo3d7+lc1 -> 615.71.09-2), so the two
# cannot drift; nothing for a version without our suffix.
nvidia_version_of() {
	printf '%s\n' "$1" | sed -n 's/^\(.*\)+stereo3d[0-9]*\(+lc[0-9]*\)\{0,1\}$/\1/p'
}

# purge_added PACKAGE...: what this run installed for the NVIDIA setup goes again (a removed package's conffiles, the
# CUDA source among them, would stay)
purge_added() {
	(($#)) || return 0
	if ! run dpkg --purge "$@"; then
		err 46 "$*"
		return 1
	fi
}

setup_nvidia() {
	local uri=developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64
	local driver decoder nvidia_version found_version other package
	local module=nvidia-kernel-open-dkms-stereo3d
	local -a policy=(sparky-stereo-nvidia-driver-lock sparky-stereo-cuda-repo) added=()
	# Nothing is changed when the edition's module is not there: the setup stops and says so.
	if ! apt-cache show --no-all-versions "$module" >"$WORK/nvidia-module" 2>&1 || ! grep -q '^Package:' "$WORK/nvidia-module"; then
		err 40 "$module"
		return 1
	fi
	found_version=$(sed -n 's/^Version: //p' "$WORK/nvidia-module" | head -n1)
	nvidia_version=$(nvidia_version_of "$found_version")
	if [[ -z $nvidia_version ]]; then
		err 41 "$found_version"
		return 1
	fi
	driver=nvidia-driver=$nvidia_version
	decoder=libnvcuvid1=$nvidia_version
	# NVIDIA's CUDA repository comes from the edition's package sparky-stereo-cuda-repo (its source, NVIDIA's key and the
	# edition's pins: CUDA updates, NVIDIA's driver stays at the module's version, Debian's own tools stay Debian's), with
	# the driver lock it depends on. Both go in a transaction of their own, so the lock and the pins are in force before
	# apt chooses any NVIDIA package; installed together with the driver, the lock came too late for NVIDIA's user space.
	# A source the person set up for NVIDIA's URI is kept: sparky-stereo-cuda-repo then writes none of its own (a second
	# source for it with another key file stops apt) and its pins apply to the person's source, since they go by origin.
	other=$(cuda_sources_elsewhere "$uri")
	if [[ -n $other ]]; then
		log "NVIDIA's CUDA repository is already configured in $other; sparky-stereo-cuda-repo keeps that source and adds the edition's pins"
	fi
	for package in "${policy[@]}"; do
		package_installed "$package" || added+=("$package")
	done
	# On a failure below, what this run installed is purged (a removed package's conffiles, the source among them, stay).
	if ((${#added[@]})) && ! apt_install "${added[@]}"; then
		purge_added "${added[@]}" || return 1
		err 42 "${added[*]}"
		return 1
	fi
	if ! run env DEBIAN_FRONTEND=noninteractive apt-get -y update; then
		purge_added "${added[@]}" || return 1
		err 43
		return 1
	fi
	if ! run env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests --simulate install "$driver" "$module" "$decoder" nvidia-vaapi-driver; then
		purge_added "${added[@]}" || return 1
		err 44 "$nvidia_version"
		return 1
	fi
	if ! apt_install "$driver" "$module" "$decoder" nvidia-vaapi-driver; then
		err 45
		return 1
	fi
	if grep -Fxq $'action\tnvidia-runtime-pm' "$WORK/plan"; then
		setup_nvidia_runtime_pm || return 1
	fi
	log "NVIDIA $nvidia_version userspace and edition open modules installed; reboot required"
}
