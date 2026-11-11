#!/bin/sh
# boot-one.sh CASE: one GRUB EFI boot of the case's disk in QEMU with OVMF (software emulation), GRUB's messages from the
# serial port into /work/out/CASE/serial.log. Runs in a container with grub-efi-amd64-bin, qemu-system-x86, ovmf, mtools,
# fdisk and e2fsprogs, as an ordinary user, /work holding this folder plus kernel (any x86 Linux image) and art.png.
set -eu
CASE=$1
OUT=/work/out/$CASE
rm -rf "$OUT"; mkdir -p "$OUT"
python3 -I /work/mkcase.py "$CASE" "$OUT"
UUID=82cc1979-cdf1-40c9-b04b-bcedc6f6a866
MODS="part_gpt part_msdos ext2 fat normal configfile search search_fs_uuid search_fs_file search_label png jpeg tga gfxterm gfxmenu all_video efi_gop video video_fb font loadenv echo linux gzio terminal boot test true sleep gettext minicmd ls cat reboot halt help regexp serial"
mkdir -p "$OUT/root/boot/grub/x86_64-efi" "$OUT/esp/EFI/BOOT"
cp /usr/lib/grub/x86_64-efi/*.mod /usr/lib/grub/x86_64-efi/*.lst "$OUT/root/boot/grub/x86_64-efi/"
grub-mkimage -O x86_64-efi -p '(hd0,gpt2)/boot/grub' -o "$OUT/esp/EFI/BOOT/BOOTX64.EFI" $MODS
truncate -s 200M "$OUT/disk.img"
sfdisk -q "$OUT/disk.img" <<SF
label: gpt
start=2048, size=65536, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
start=67584, size=327680, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
SF
truncate -s 32M "$OUT/esp.img"; mformat -i "$OUT/esp.img" ::; mcopy -s -i "$OUT/esp.img" "$OUT/esp/EFI" ::
dd if="$OUT/esp.img" of="$OUT/disk.img" bs=512 seek=2048 conv=notrunc status=none
mke2fs -q -t ext2 -U $UUID -d "$OUT/root" -E offset=$((67584*512)) "$OUT/disk.img" 160M
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$OUT/vars.fd"
qemu-system-x86_64 -machine q35 -cpu max -m 1024 -smp 2 \
  -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,unit=1,file="$OUT/vars.fd" \
  -drive file="$OUT/disk.img",format=raw,if=virtio \
  -vga std -display none -serial file:"$OUT/serial.log" -no-reboot &
QP=$!
# the kernel takes over within seconds; a case that stops for a key is waiting at "Press any key"
sleep "${GRUB_WAIT:-25}"
kill $QP 2>/dev/null || true
wait $QP 2>/dev/null || true
rm -f "$OUT/disk.img" "$OUT/esp.img"
