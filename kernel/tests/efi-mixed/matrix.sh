#!/bin/bash
# matrix.sh W TAG VMLINUZ SYSMAP : one kernel through every firmware and loader of the rig, KASLR on (inside the rig image)
#   ia32-grub   32-bit OVMF, GRUB 2.14 i386-efi (the decompressor chooses the address: the case of the fix)  N_IA32 boots
#   ia32-direct 32-bit OVMF, QEMU -kernel (the EFI stub through the 32-bit handover entry)                  N_OTHER
#   x64-grub    64-bit OVMF, GRUB 2.14 x86_64-efi                                                           N_OTHER
#   x64-direct  64-bit OVMF, QEMU -kernel (the EFI stub)                                                    N_OTHER
#   bios-direct SeaBIOS, QEMU -kernel (the 16-bit boot protocol, no EFI)                                     N_OTHER
set -u
W=$1 TAG=$2 K=$3 MAP=$4; R=/rig; OUT=$W/runs/matrix-$TAG
N_IA32=${N_IA32:-100}; N_OTHER=${N_OTHER:-20}; CASES=${CASES:-ia32-grub ia32-direct x64-grub x64-direct bios-direct}
mkdir -p "$OUT" "$W/disks"
C="console=ttyS0,115200 panic=0"
for c in $CASES; do
	case $c in
	ia32-grub) $R/mkgrubdisk.sh "$W/disks/$TAG-ia32.img" "$K" "$W/initrd-probe.img" "$C" i386-efi
		python3 -I $R/boots.py --loader grub --grub-disk "$W/disks/$TAG-ia32.img" --sysmap "$MAP" --out "$OUT/$c" --count $N_IA32 --timeout 60 > "$OUT/$c.log" 2>&1
		rm -f "$W/disks/$TAG-ia32.img" ;;
	ia32-direct) python3 -I $R/boots.py --loader direct --kernel "$K" --initrd "$W/initrd-probe.img" --sysmap "$MAP" --out "$OUT/$c" --count $N_OTHER --timeout 60 > "$OUT/$c.log" 2>&1 ;;
	x64-grub) $R/mkgrubdisk.sh "$W/disks/$TAG-x64.img" "$K" "$W/initrd-probe.img" "$C" x86_64-efi
		python3 -I $R/boots.py --fw ovmf --loader grub --grub-disk "$W/disks/$TAG-x64.img" --sysmap "$MAP" --out "$OUT/$c" --count $N_OTHER --timeout 60 > "$OUT/$c.log" 2>&1
		rm -f "$W/disks/$TAG-x64.img" ;;
	x64-direct) python3 -I $R/boots.py --fw ovmf --loader direct --kernel "$K" --initrd "$W/initrd-probe.img" --sysmap "$MAP" --out "$OUT/$c" --count $N_OTHER --timeout 60 > "$OUT/$c.log" 2>&1 ;;
	bios-direct) python3 -I $R/boots.py --fw seabios --loader direct --kernel "$K" --initrd "$W/initrd-probe.img" --sysmap "$MAP" --out "$OUT/$c" --count $N_OTHER --timeout 60 > "$OUT/$c.log" 2>&1 ;;
	esac
	python3 -I $R/summary.py "$OUT/$c"
done
