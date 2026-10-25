#!/bin/sh
# Offline work on an installed test disk (raw), in the build container (privileged, for a loop device):
#   disk-tool.sh DISK getty      enable a login on the serial port (serial-getty@ttyS0) for the checks
#   disk-tool.sh DISK fallback   print the sha256 of every file in the EFI system partition's EFI/Boot
#   disk-tool.sh DISK grubcfg    print the installed /boot/grub/grub.cfg's menu entries and background lines
# The root file system is the largest ext4 partition. Nothing else on the disk is changed.
set -eu
DISK=$(readlink -f "$1"); ACT=$2
exec docker run --rm --privileged --name "${NAME:-beta-iso-lutz}-disktool" -v "$(dirname "$DISK"):/d" "${IMAGE:-beta-iso-lutz-build:1}" sh -c '
set -eu
for i in $(seq 0 127); do [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i; done
D=/d/'"$(basename "$DISK")"'
parts=$(sfdisk -J "$D" | python3 -c "import json,sys; t=json.load(sys.stdin)[\"partitiontable\"]; [print(p[\"start\"], p[\"size\"], p[\"type\"]) for p in t[\"partitions\"]]")
root= esp=
echo "$parts" | while read -r start size type; do echo "$start $size $type"; done > /tmp/p
best=0
while read -r start size type; do
	case $type in
		C12A7328-F81F-11D2-BA4B-00A0C93EC93B) esp=$start ;;
		0FC63DAF-8483-4772-8E79-3D69D8477DE4) [ "$size" -gt "$best" ] && { best=$size; root=$start; } ;;
	esac
done < /tmp/p
mkdir -p /mnt/r /mnt/e
case '"$ACT"' in
getty)
	mount -o offset=$((root * 512)) "$D" /mnt/r
	mkdir -p /mnt/r/etc/systemd/system/getty.target.wants
	ln -sf /usr/lib/systemd/system/serial-getty@.service /mnt/r/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service
	ls -l /mnt/r/etc/systemd/system/getty.target.wants/
	umount /mnt/r ;;
fallback)
	mount -o ro,offset=$((esp * 512)) "$D" /mnt/e
	find /mnt/e -iname "*.efi" -o -iname "grub.cfg" -o -iname "*.cer" -o -iname "*.der" | sort | while read -r f; do sha256sum "$f"; done
	umount /mnt/e ;;
grubcfg)
	mount -o ro,offset=$((root * 512)) "$D" /mnt/r
	grep -E "^(menuentry|submenu)|background_image|set lang|set menu_color|GRUB_BACKGROUND|insmod png" /mnt/r/boot/grub/grub.cfg
	grep -h "" /mnt/r/etc/default/locale 2>/dev/null
	umount /mnt/r ;;
esac
'
