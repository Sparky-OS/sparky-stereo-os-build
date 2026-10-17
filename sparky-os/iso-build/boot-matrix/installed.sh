#!/bin/sh
# Starts an installed test system (a raw disk), headless, no stick, offline, in the background:
#   installed.sh DISK VARS OUTDIR [sb|ovmf] [stereo|std]
# sb: Secure Boot firmware (VARS should have the edition's key enrolled); ovmf: plain UEFI.
# stereo: QEMU's stereo virtio-vga at 1920x1080 and QEMU's own trace of every scanout and mode set
# (OUTDIR/qemu-trace.log, the boot chain lane's events); std: the standard VGA.
# OUTDIR gets qmp.sock, serial.sock (a getty there needs serial-getty@ttyS0 enabled in the system),
# VARS.fd (a copy), cmdline.txt and qemu.log. Nothing touches a display.
set -eu
DISK=$(readlink -f "$1"); VARS=$(readlink -f "$2"); OUT=$3; FW=${4:-sb}; GPU=${5:-std}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -f "$OUT/qmp.sock" "$OUT/serial.sock"
[ -f "$OUT/VARS.fd" ] || cp "$VARS" "$OUT/VARS.fd"
F=$HERE/fw/ovmf-forky/usr/share/OVMF
case $FW in
sb) M="-machine q35,accel=kvm,smm=on -global driver=cfi.pflash01,property=secure,value=on"; CODE=$F/OVMF_CODE_4M.secboot.fd ;;
*) M="-machine q35,accel=kvm"; CODE=$F/OVMF_CODE_4M.fd ;;
esac
case $GPU in
stereo) G="-vga none -device virtio-vga,xres=1920,yres=1080,stereo=on,max_hostmem=1G -trace events=$HERE/boot-chain-events.txt,file=$OUT/qemu-trace.log -msg timestamp=on" ;;
*) G="-vga std" ;;
esac
# shellcheck disable=SC2086
set -- qemu-system-x86_64 -name beta-iso-lutz-installed $M -cpu host -smp 4 -m 8G -display none $G \
	-serial "unix:$OUT/serial.sock,server=on,wait=off" -monitor none -qmp "unix:$OUT/qmp.sock,server=on,wait=off" \
	-nodefaults -device qemu-xhci,id=xin -device usb-kbd,bus=xin.0 -device usb-tablet,bus=xin.0 \
	-netdev user,id=n0,restrict=on -device virtio-net-pci,netdev=n0 \
	-drive if=pflash,format=raw,unit=0,readonly=on,file=$CODE -drive if=pflash,format=raw,unit=1,file=$OUT/VARS.fd \
	-drive file=$DISK,if=none,id=d0,format=raw,discard=unmap -device virtio-blk-pci,drive=d0,bootindex=1
echo "$*" > "$OUT/cmdline.txt"
date -u +%Y-%m-%dT%H:%M:%S.%NZ > "$OUT/t0"
setsid "$@" > "$OUT/qemu.log" 2>&1 < /dev/null &
echo "started: $!"
