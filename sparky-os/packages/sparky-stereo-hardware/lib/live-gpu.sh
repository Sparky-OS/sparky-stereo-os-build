#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/15
# The live session's NVIDIA choice, sourced by the initramfs (busybox sh) and by the tests.
# The edition's NVIDIA driver (open modules, 615) runs Turing and newer; older, unknown or mixed
# NVIDIA graphics get nouveau, as Hardware Setup decides on an installed system (detect.py).

# live_gpu_decide SYSFS CONFDIR SECUREBOOT CMDLINE: prints "<driver> <reason>"
# driver: nvidia, nouveau or none; reason: supported, older, kernel, unsigned, forced, no-nvidia
# CONFDIR holds nvidia-open.ids and, written for each kernel when its initramfs is made,
# nvidia-modules (the kernel has the NVIDIA modules) and nvidia-signer (who signed them).
live_gpu_decide() {
	sys=$1 conf=$2 sb=$3 forced=
	for x in $4; do
		case $x in sparky.gpu=*) forced=${x#sparky.gpu=} ;; esac
	done
	nv=0 old=0
	for d in "$sys"/bus/pci/devices/*; do
		[ "$(cat "$d/vendor" 2>/dev/null)" = 0x10de ] || continue
		case $(cat "$d/class" 2>/dev/null) in 0x03*) ;; *) continue ;; esac
		nv=$((nv + 1))
		dev=$(cat "$d/device"); sv=$(cat "$d/subsystem_vendor" 2>/dev/null); sd=$(cat "$d/subsystem_device" 2>/dev/null)
		grep -qx -e "${dev#0x}" -e "${dev#0x} ${sv#0x} ${sd#0x}" "$conf/nvidia-open.ids" || old=$((old + 1))
	done
	if [ "$nv" = 0 ]; then
		echo "none no-nvidia"
	elif [ "$forced" = nouveau ]; then
		echo "nouveau forced"
	elif [ ! -f "$conf/nvidia-modules" ]; then
		echo "nouveau kernel"
	elif [ "$forced" = nvidia ]; then
		echo "nvidia forced"
	elif [ "$old" != 0 ]; then
		echo "nouveau older"
	elif [ "$sb" = 1 ] && ! grep -q '^Sparky Stereo OS Secure Boot' "$conf/nvidia-signer" 2>/dev/null; then
		echo "nouveau unsigned"
	else
		echo "nvidia supported"
	fi
}

# live_gpu_secureboot SYSFS: prints 1 when the firmware booted with Secure Boot on, else 0
live_gpu_secureboot() {
	v=$(ls "$1"/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null)
	if [ -n "$v" ] && [ "$(od -An -t u1 -j4 -N1 "$v" 2>/dev/null | tr -d ' ')" = 1 ]; then
		echo 1
	else
		echo 0
	fi
}

# live_gpu_modprobe DRIVER: the modprobe.d lines for the choice
live_gpu_modprobe() {
	case $1 in
	nvidia) printf 'blacklist nouveau\noptions nouveau modeset=0\n' ;;
	nouveau) printf 'install nvidia /bin/false\ninstall nvidia_drm /bin/false\ninstall nvidia_modeset /bin/false\ninstall nvidia_uvm /bin/false\n' ;;
	esac
}

# live_gpu_apply DRIVER ROOT: writes the choice into ROOT/etc/modprobe.d; for nouveau, every other
# modprobe.d file that blacklists it (NVIDIA's packages ship one) is masked by an empty file of the
# same name in /etc, or set aside when it is in /etc itself (a live root lives in memory)
live_gpu_apply() {
	mkdir -p "$2/etc/modprobe.d"
	live_gpu_modprobe "$1" > "$2/etc/modprobe.d/sparky-stereo-live-gpu.conf"
	[ "$1" = nouveau ] || return 0
	for f in "$2"/usr/lib/modprobe.d/*.conf "$2"/lib/modprobe.d/*.conf; do
		[ -f "$f" ] && grep -q '^[[:space:]]*blacklist[[:space:]]\+nouveau' "$f" && : > "$2/etc/modprobe.d/${f##*/}"
	done
	for f in "$2"/etc/modprobe.d/*.conf; do
		[ -s "$f" ] && grep -q '^[[:space:]]*blacklist[[:space:]]\+nouveau' "$f" && mv "$f" "$f.sparky-live-off"
	done
	return 0
}
