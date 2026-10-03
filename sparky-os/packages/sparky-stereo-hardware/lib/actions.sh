#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03

log() { printf '%s\n' "$*"; }
run() { printf 'RUN'; printf ' %q' "$@"; printf '\n'; "$@"; }
apt_install() { run env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install "$@"; }

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
		mkdir -p "$ROOT/etc/modules-load.d"
		printf '%s\n' "${modules[@]}" >"$ROOT/etc/modules-load.d/sparky-stereo-sensors.conf"
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
	mkdir -p "$ROOT/etc/modprobe.d"
	printf '%s\n' 'options snd_hda_intel enable_msi=1' >"$ROOT/etc/modprobe.d/sparky-stereo-creative.conf"
	log 'Creative firmware verified; snd_hda_intel enable_msi=1 applies after reboot'
}

setup_nvidia() {
	local base=https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64
	local key="$ROOT/etc/apt/keyrings/sparky-stereo-cuda.gpg"
	local source="$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
	local pin="$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda"
	local driver=nvidia-driver=615.71.09-2
	local module=nvidia-kernel-open-dkms-stereo3d
	# Do not start a repository change if the edition's module is unavailable.
	if ! apt-cache show "$module" >"$WORK/nvidia-module" 2>&1 || ! grep -q '^Package:' "$WORK/nvidia-module"; then
		log 'FALLBACK edition NVIDIA module unavailable; nouveau firmware installed'
		return 0
	fi
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
	mkdir -p "${key%/*}" "${source%/*}" "${pin%/*}"
	# Back up our previous files so a failed preflight restores the previous policy.
	for file in "$key" "$source" "$pin"; do
		[[ ! -e "$file" ]] || cp -p "$file" "$WORK/${file##*/}.previous"
	done
	install -m644 "$WORK/cuda.gpg" "$key"
	cat >"$source" <<EOF
Types: deb
URIs: $base/
Suites: /
Architectures: amd64
Signed-By: /etc/apt/keyrings/sparky-stereo-cuda.gpg
EOF
	cat >"$pin" <<'EOF'
Package: *
Pin: origin developer.download.nvidia.com
Pin-Priority: 1002
EOF
	if ! run env DEBIAN_FRONTEND=noninteractive apt-get -y update ||
		! run env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests --simulate install "$driver" "$module"; then
		for file in "$key" "$source" "$pin"; do
			if [[ -e "$WORK/${file##*/}.previous" ]]; then
				cp -p "$WORK/${file##*/}.previous" "$file"
			else
				rm -f "$file"
			fi
		done
		log 'FALLBACK NVIDIA preflight failed; previous repository policy restored; nouveau firmware installed'
		return 0
	fi
	if ! apt_install "$driver" "$module"; then
		log 'ERROR NVIDIA transaction failed; inspect apt/dpkg state before reboot; nouveau firmware is present'
		return 1
	fi
	log 'NVIDIA 615.71.09 userspace and edition open modules installed; reboot required'
}
