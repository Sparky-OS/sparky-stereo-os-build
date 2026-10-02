#!/bin/bash
# Hands the RTX 3060 (01:00.0 and its HDMI audio 01:00.1) to the development VM while the host
# runs, and takes it back; nothing persists, a reboot also gives it back (Daniel, 2026-10-02).
# The VM then drives the TV on the card's HDMI port (the KDL-46EX725) with the edition's own
# NVIDIA stack: the hardware path tested on real hardware.
# KWin must not hold the card: log in with ~/.config/plasma-workspace/env/kwin-igpu.sh
# (KWIN_DRM_DEVICES on the iGPU) first. While the VM has the card, the host has no NVIDIA GPU:
# the services that use it are stopped by give and started again by take.
#
#   sudo gpu-vfio.sh give      stop the card's users, bind both devices to vfio-pci
#   sudo gpu-vfio.sh take      back to nvidia and snd_hda_intel, restart what give stopped
#   gpu-vfio.sh status         drivers in use and who holds the card
# Then the VM: GPU=nvidia sparky-vm.sh run
set -euo pipefail
DEVS=(0000:01:00.0 0000:01:00.1)
CARD=/dev/dri/by-path/pci-0000:01:00.0-card
STATE=/run/sparky-vm-vfio.stopped
SERVICES=(nvidia-persistenced coolercontrold netdata)
CONTAINERS=(open-webui)
VMUSER=${SUDO_USER:-daniel}

need_root() { [ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }; }
holders() { fuser "$CARD" /dev/nvidia* 2>/dev/null | tr -s ' ' '\n' | grep . | sort -u | while read -r p; do ps -o comm= -p "$p"; done | sort -u; }

case ${1:-} in
give)
	need_root
	if fuser "$CARD" 2>/dev/null | grep -q .; then
		ps -o comm= -p "$(fuser "$CARD" 2>/dev/null | tr -s ' ' ',' | sed 's/^,//')" | grep -qx kwin_wayland &&
			{ echo "KWin holds the card: log in with kwin-igpu.sh first"; exit 1; }
	fi
	: >"$STATE"
	for s in "${SERVICES[@]}"; do
		systemctl is-active -q "$s" && { systemctl stop "$s"; echo "service $s" >>"$STATE"; }
	done
	for c in "${CONTAINERS[@]}"; do
		[ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = true ] &&
			{ docker stop "$c" >/dev/null; echo "container $c" >>"$STATE"; }
	done
	h=$(holders)
	[ -n "$h" ] && { echo "still holding the card (close them, then run give again):"; echo "$h"; exit 1; }
	modprobe vfio-pci
	for d in "${DEVS[@]}"; do
		echo vfio-pci >"/sys/bus/pci/devices/$d/driver_override"
		[ -e "/sys/bus/pci/devices/$d/driver" ] && echo "$d" >"/sys/bus/pci/devices/$d/driver/unbind"
		echo "$d" >/sys/bus/pci/drivers_probe
	done
	g=$(basename "$(readlink /sys/bus/pci/devices/${DEVS[0]}/iommu_group)")
	chown "$VMUSER" "/dev/vfio/$g"
	echo "done: the card is vfio-pci's (group $g); start the VM with GPU=nvidia sparky-vm.sh run"
	;;
take)
	need_root
	for d in "${DEVS[@]}"; do
		echo >"/sys/bus/pci/devices/$d/driver_override"
		[ -e "/sys/bus/pci/devices/$d/driver" ] && echo "$d" >"/sys/bus/pci/devices/$d/driver/unbind"
		echo "$d" >/sys/bus/pci/drivers_probe
	done
	if [ -f "$STATE" ]; then
		while read -r kind name; do
			case $kind in
			service) systemctl start "$name" ;;
			container) docker start "$name" >/dev/null ;;
			esac
		done <"$STATE"
		rm -f "$STATE"
	fi
	echo "done: the card is the host's again (KWin uses it after kwin-igpu.sh is removed and you log in again)"
	;;
status)
	lspci -nnk -s 01:00 | grep -E '^[0-9]|driver in use'
	echo "holding the card: $(holders | tr '\n' ' ')"
	;;
*) sed -n '2,15p' "$0"; exit 1 ;;
esac
