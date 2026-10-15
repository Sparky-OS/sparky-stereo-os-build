#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/15
# Tests the live session's NVIDIA choice (lib/live-gpu.sh) on fixture sysfs trees.
# Usage: tests/live-gpu.sh (run it with the shell under test: busybox sh, dash)
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/lib/live-gpu.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
pci() { # pci SYS NAME VENDOR DEVICE CLASS SUBVENDOR SUBDEVICE
	d=$1/bus/pci/devices/$2; mkdir -p "$d"
	echo "0x$3" > "$d/vendor"; echo "0x$4" > "$d/device"; echo "0x$5" > "$d/class"
	echo "0x$6" > "$d/subsystem_vendor"; echo "0x$7" > "$d/subsystem_device"
}
conf() { # conf DIR MODULES(0/1) SIGNER
	mkdir -p "$1"; cp "$HERE/share/nvidia-open.ids" "$1/"
	[ "$2" = 1 ] && echo /lib/modules/x/updates/dkms/nvidia.ko.xz > "$1/nvidia-modules"
	[ -n "$3" ] && echo "$3" > "$1/nvidia-signer"
	return 0
}
ours="Sparky Stereo OS Secure Boot 2026"
s=$T/qemu; pci $s 0000:00:01.0 1234 1111 030000 1af4 1100; conf $T/c1 1 "$ours"
check "QEMU, no NVIDIA" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "none no-nvidia"
s=$T/turing; pci $s 0000:01:00.0 10de 1eb1 030000 10de 12a0; pci $s 0000:01:00.1 10de 10f8 040300 10de 12a0
check "Quadro RTX 4000, modules, Secure Boot off" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "nvidia supported"
check "Quadro RTX 4000, Secure Boot on, our signature" "$(live_gpu_decide $s $T/c1 1 'boot=live')" "nvidia supported"
conf $T/c2 1 "DKMS module signing key"
check "Quadro RTX 4000, Secure Boot on, DKMS's own key" "$(live_gpu_decide $s $T/c2 1 'boot=live')" "nouveau unsigned"
check "Quadro RTX 4000, Secure Boot off, DKMS's own key" "$(live_gpu_decide $s $T/c2 0 'boot=live')" "nvidia supported"
conf $T/c3 0 ""
check "Quadro RTX 4000, Debian's kernel (no NVIDIA modules)" "$(live_gpu_decide $s $T/c3 1 'boot=live')" "nouveau kernel"
check "Quadro RTX 4000, sparky.gpu=nouveau" "$(live_gpu_decide $s $T/c1 0 'boot=live sparky.gpu=nouveau')" "nouveau forced"
s=$T/pascal; pci $s 0000:01:00.0 10de 1bb1 030000 10de 11a3
check "Quadro P4000 (Pascal)" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "nouveau older"
check "Quadro P4000, sparky.gpu=nvidia" "$(live_gpu_decide $s $T/c1 0 'boot=live sparky.gpu=nvidia')" "nvidia forced"
check "Quadro P4000, sparky.gpu=nvidia, no modules" "$(live_gpu_decide $s $T/c3 0 'boot=live sparky.gpu=nvidia')" "nouveau kernel"
s=$T/mixed; pci $s 0000:01:00.0 10de 1eb1 030000 10de 12a0; pci $s 0000:02:00.0 10de 1bb1 030000 10de 11a3
check "Turing and Pascal together" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "nouveau older"
s=$T/bmc; pci $s 0000:03:00.0 1a03 2000 030000 1043 85fa; pci $s 0000:41:00.0 10de 1eb1 030000 10de 12a0
check "ASPEED BMC VGA and a Quadro RTX 4000" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "nvidia supported"
s=$T/sub; pci $s 0000:01:00.0 10de 1e78 030000 10de 13d8
check "1e78 with a listed subsystem" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "nvidia supported"
s=$T/sub2; pci $s 0000:01:00.0 10de 1e78 030000 1043 ffff
check "1e78 with an unlisted subsystem" "$(live_gpu_decide $s $T/c1 0 'boot=live')" "nouveau older"
# Secure Boot state from the firmware variable (4 bytes of attributes, then the value)
v=$T/sb1/firmware/efi/efivars; mkdir -p $v; printf '\007\000\000\000\001' > $v/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
check "SecureBoot variable 1" "$(live_gpu_secureboot $T/sb1)" 1
v=$T/sb0/firmware/efi/efivars; mkdir -p $v; printf '\007\000\000\000\000' > $v/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
check "SecureBoot variable 0" "$(live_gpu_secureboot $T/sb0)" 0
check "no SecureBoot variable (BIOS)" "$(live_gpu_secureboot $T/none)" 0
# applying the choice to a root
r=$T/root1; mkdir -p $r/usr/lib/modprobe.d $r/etc/modprobe.d
echo "blacklist nouveau" > $r/usr/lib/modprobe.d/nvidia-blacklists-nouveau.conf
echo "options nvidia-drm modeset=1" > $r/etc/modprobe.d/nvidia.conf
live_gpu_apply nouveau $r
check "nouveau: NVIDIA's blacklist in /usr/lib masked" "$(wc -c < $r/etc/modprobe.d/nvidia-blacklists-nouveau.conf | tr -d ' ')" 0
check "nouveau: nvidia modules refused" "$(grep -c '^install nvidia' $r/etc/modprobe.d/sparky-stereo-live-gpu.conf)" 4
check "nouveau: other modprobe.d files kept" "$(cat $r/etc/modprobe.d/nvidia.conf)" "options nvidia-drm modeset=1"
r=$T/root2; mkdir -p $r/etc/modprobe.d; echo "blacklist nouveau" > $r/etc/modprobe.d/nvidia-blacklists-nouveau.conf
live_gpu_apply nouveau $r
check "nouveau: NVIDIA's blacklist in /etc set aside" "$(ls $r/etc/modprobe.d | tr '\n' ' ')" "nvidia-blacklists-nouveau.conf.sparky-live-off sparky-stereo-live-gpu.conf "
r=$T/root3; live_gpu_apply nvidia $r
check "nvidia: nouveau blacklisted" "$(head -1 $r/etc/modprobe.d/sparky-stereo-live-gpu.conf)" "blacklist nouveau"
r=$T/root4; live_gpu_apply none $r
check "no NVIDIA: empty file" "$(wc -c < $r/etc/modprobe.d/sparky-stereo-live-gpu.conf | tr -d ' ')" 0
echo "live-gpu: $pass passed, $fail failed"
[ "$fail" = 0 ]
