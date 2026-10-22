#!/bin/sh
# ia32 (32-bit UEFI) boot of the stick, with GRUB 2.14 from a FAT disk that the firmware starts first (FAT) or with
# the stick's own GRUB (FAT=); the stick is the CD. APPEND: options added to the first entry's linux line. Menu entry: Enter at 15 s and 25 s. Screenshots every 45 s, serial to OUT/serial.log.
#   run.sh OUT [ISO]
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -eu
L=${SPARKY_WORKSPACES:?}/beta-iso-lutz
OUT=$1; ISO=${2:-/mnt/build/beta-iso-lutz/out/sparky-stereo-os-9-mashtabba-beta2-x86_64.iso}
# FAT: the GRUB 2.14 test disk (default); FAT= (empty) boots the stick's own GRUB
FAT=${FAT-$L/ia32-grub/ia32-grub214.img}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
cp $L/boot-matrix/fw/vars/ia32-empty.vars "$OUT/VARS.fd"
rm -f "$OUT/qmp.sock"
qemu-system-x86_64 -name beta-iso-lutz-ia32-grub214 -machine q35,accel=kvm -cpu host -smp 4 -m 4G -display none -vga std \
	-serial "file:$OUT/serial.log" -monitor none -qmp "unix:$OUT/qmp.sock,server=on,wait=off" -no-reboot -nodefaults \
	-device qemu-xhci,id=xin -device usb-kbd,bus=xin.0 -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
	-drive if=pflash,format=raw,unit=0,readonly=on,file=$L/boot-matrix/fw/ovmf32-trixie/usr/share/OVMF/OVMF32_CODE_4M.fd \
	-drive if=pflash,format=raw,unit=1,file="$OUT/VARS.fd" \
	${FAT:+-drive file=$FAT,if=none,id=f0,format=raw,readonly=on -device virtio-blk-pci,drive=f0,bootindex=0} \
	-drive file="$ISO",media=cdrom,if=none,id=m0,readonly=on,format=raw -device ide-cd,drive=m0,bootindex=1 \
	> "$OUT/qemu.log" 2>&1 &
QP=$!
V=$L/boot-matrix/vmctl.py
sleep 15; python3 $V "$OUT/qmp.sock" shot "$OUT/m15.png" || true
if [ -n "${APPEND:-}" ]; then
	# the first entry's linux line gets APPEND before its "; then" (GRUB's editor: line 3, end, six to the left)
	python3 $V "$OUT/qmp.sock" key e; sleep 1
	for k in down down ctrl+e left left left left left left; do python3 $V "$OUT/qmp.sock" key $k; sleep 0.2; done
	python3 $V "$OUT/qmp.sock" type " $APPEND"; sleep 1
	python3 $V "$OUT/qmp.sock" shot "$OUT/edited.png"
	python3 $V "$OUT/qmp.sock" key ctrl+x
else
	python3 $V "$OUT/qmp.sock" key ret || true
	sleep 10; python3 $V "$OUT/qmp.sock" shot "$OUT/m25.png" || true
	python3 $V "$OUT/qmp.sock" key ret || true
fi
for t in 45 90 135 180 225; do sleep 45; python3 $V "$OUT/qmp.sock" shot "$OUT/t$t.png" 2>/dev/null || { echo "qemu gone at $t"; break; }; done
python3 $V "$OUT/qmp.sock" quit 2>/dev/null || true
wait $QP 2>/dev/null || true
echo done
