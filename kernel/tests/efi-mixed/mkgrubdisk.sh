#!/bin/bash
# mkgrubdisk.sh OUT.img VMLINUZ INITRD "CMDLINE" [i386-efi|x86_64-efi|i386-pc]
# A FAT disk image that boots VMLINUZ through Debian's GRUB (the ISO's loader): EFI/BOOT/BOOTIA32.EFI (or BOOTX64.EFI)
# from grub-mkstandalone, the kernel and initrd beside it; serial console on ttyS0 for GRUB and the kernel.
set -euo pipefail
OUT=$1 K=$2 I=$3 CMD=$4 PLAT=${5:-i386-efi}
T=$(mktemp -d)
cat > "$T/grub.cfg" <<CFG
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
set timeout=0
search --no-floppy --file --set=root /efi246.tag
echo "EFI246 grub platform \$grub_platform cpu \$grub_cpu"
linux /vmlinuz $CMD
initrd /initrd.img
boot
CFG
case $PLAT in
  i386-efi) EFI=BOOTIA32.EFI ;;
  x86_64-efi) EFI=BOOTX64.EFI ;;
esac
SZ=$(( ( $(stat -c %s "$K") + $(stat -c %s "$I") ) / 1048576 + 48 ))
truncate -s ${SZ}M "$OUT"
mkfs.vfat -F 32 -n EFI246 "$OUT" >/dev/null
grub-mkstandalone -O "$PLAT" --modules="part_gpt part_msdos fat search search_fs_file linux serial terminal echo normal" \
    --locales= --fonts= --themes= -o "$T/$EFI" "boot/grub/grub.cfg=$T/grub.cfg"
mmd -i "$OUT" ::/EFI ::/EFI/BOOT
mcopy -i "$OUT" "$T/$EFI" ::/EFI/BOOT/$EFI
mcopy -i "$OUT" "$K" ::/vmlinuz
mcopy -i "$OUT" "$I" ::/initrd.img
echo tag > "$T/efi246.tag"; mcopy -i "$OUT" "$T/efi246.tag" ::/efi246.tag
rm -rf "$T"
