#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10

log() { printf '%s\n' "$*"; }
run() { printf 'RUN'; printf ' %q' "$@"; printf '\n'; "$@"; }
apt_install() { run env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install "$@"; }

setup_rig_driver() {
	local package=$1 kernel headers
	case "$package" in hid-tmff2-dkms|hid-fanatecff-dkms|new-lg4ff-dkms) ;; *) return 1 ;; esac
	kernel=$(uname -r)
	[[ $kernel =~ ^[a-zA-Z0-9][a-zA-Z0-9.+_-]*$ ]] || return 1
	headers="linux-headers-$kernel"
	apt_install --simulate "$headers" "$package" || return 1
	apt_install "$headers" "$package"
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
		log 'ERROR sensors-detect failed'
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
				log "ERROR sensor module $module absent from sysfs after modprobe"
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
		[[ -s "$ROOT/usr/lib/firmware/updates/$firmware" ]] || { log "ERROR missing Creative $firmware"; return 1; }
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
	local action
	run powerprofilesctl list-actions >"$WORK/power-actions" || return 1
	for action in "$@"; do
		if ! grep -Fxq "Name: $action" "$WORK/power-actions"; then
			log "UNSUPPORTED PPD action $action is not exposed; no replacement GPU tuning applied"
			continue
		fi
		if ! ppd_action_enabled "$action" "$WORK/power-actions"; then
			run powerprofilesctl configure-action "$action" --enable || return 1
		fi
		run powerprofilesctl list-actions >"$WORK/power-actions" || return 1
		ppd_action_enabled "$action" "$WORK/power-actions" || { log "ERROR PPD action $action not enabled"; return 1; }
		log "VERIFIED PPD action $action enabled"
	done
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

setup_nvidia() {
	local base=https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64
	local key="$ROOT/etc/apt/keyrings/sparky-stereo-cuda.gpg"
	local source="$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
	local pin="$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda"
	local driver nvidia_version
	local module=nvidia-kernel-open-dkms-stereo3d
	local file
	# Do not start a repository change if the edition's module is unavailable.
	if ! apt-cache show --no-all-versions "$module" >"$WORK/nvidia-module" 2>&1 || ! grep -q '^Package:' "$WORK/nvidia-module"; then
		log 'FALLBACK edition NVIDIA module unavailable; nouveau firmware installed'
		return 0
	fi
	# The userspace driver is NVIDIA's version the module is built for: the module's version
	# without our +stereo3d suffix (615.71.09-2+stereo3d4 -> 615.71.09-2), so the two cannot drift.
	nvidia_version=$(sed -n 's/^Version: \(.*\)+stereo3d[0-9]*$/\1/p' "$WORK/nvidia-module" | head -n1)
	if [[ -z $nvidia_version ]]; then
		log 'FALLBACK edition NVIDIA module has no NVIDIA version; nouveau firmware installed'
		return 0
	fi
	driver=nvidia-driver=$nvidia_version
	if ! run curl --fail --location --max-time 60 "$base/cuda-keyring_1.1-1_all.deb" -o "$WORK/cuda-keyring.deb"; then
		log 'FALLBACK CUDA key download failed; nouveau firmware installed'
		return 0
	fi
	if ! printf '%s  %s\n' "$CUDA_KEY_SHA256" "$WORK/cuda-keyring.deb" | sha256sum -c -; then
		log 'FALLBACK CUDA key checksum mismatch; nouveau firmware installed'
		return 0
	fi
	if ! dpkg-deb --fsys-tarfile "$WORK/cuda-keyring.deb" | tar -xO ./usr/share/keyrings/cuda-archive-keyring.gpg >"$WORK/cuda.gpg"; then
		log 'FALLBACK CUDA key extraction failed; nouveau firmware installed'
		return 0
	fi
	mkdir -p "${key%/*}" "${source%/*}" "${pin%/*}" || return 1
	# Back up our previous files so a failed preflight restores the previous policy.
	for file in "$key" "$source" "$pin"; do
		[[ ! -e "$file" ]] || cp -p "$file" "$WORK/${file##*/}.previous" || return 1
	done
	install -m644 "$WORK/cuda.gpg" "$key" || return 1
	cat >"$source" <<EOF || return 1
Types: deb
URIs: $base/
Suites: /
Architectures: amd64
Signed-By: /etc/apt/keyrings/sparky-stereo-cuda.gpg
EOF
	cat >"$pin" <<'EOF' || return 1
Package: *
Pin: origin developer.download.nvidia.com
Pin-Priority: 1002
EOF
	if ! run env DEBIAN_FRONTEND=noninteractive apt-get -y update ||
		! run env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests --simulate install "$driver" "$module"; then
		for file in "$key" "$source" "$pin"; do
			if [[ -e "$WORK/${file##*/}.previous" ]]; then
				cp -p "$WORK/${file##*/}.previous" "$file" || return 1
			else
				rm -f "$file" || return 1
			fi
		done
		log 'FALLBACK NVIDIA preflight failed; previous repository policy restored; nouveau firmware installed'
		return 0
	fi
	if ! apt_install "$driver" "$module"; then
		log 'ERROR NVIDIA transaction failed; inspect apt/dpkg state before reboot; nouveau firmware is present'
		return 1
	fi
	if grep -Fxq $'action\tnvidia-runtime-pm' "$WORK/plan"; then
		setup_nvidia_runtime_pm || return 1
	fi
	log "NVIDIA $nvidia_version userspace and edition open modules installed; reboot required"
}
