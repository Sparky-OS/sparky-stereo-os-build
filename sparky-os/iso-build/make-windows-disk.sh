#!/bin/sh
# A test disk laid out the way Windows 10 and 11 install themselves on UEFI, after "Shrink Volume":
#   1 EFI system partition, 100 MiB, FAT32 "SYSTEM", with EFI/Microsoft/Boot/bootmgfw.efi and BCD and the
#     fallback EFI/Boot/bootx64.efi
#   2 Microsoft reserved partition, 16 MiB
#   3 "Windows" (C:), NTFS, 20 GiB, with Windows/System32 and Users/Lutz/Documents/Hallo Welt.txt
#   - free space, where Windows was shrunk
#   4 Windows recovery, NTFS, 600 MiB, at the end of the disk
# The Windows boot manager is a stand-in: a small EFI program (GRUB, standalone) that prints that it is the
# stand-in, so the installed system's menu entry can be seen chainloading it. It is not Windows.
# Runs as root in beta-iso-lutz-build:1 (privileged, for a loop device). Usage: make-windows-disk.sh FILE [SIZE_GIB]
set -eu
F=$1; SIZE=${2:-48}
rm -f "$F"; truncate -s ${SIZE}G "$F"
sfdisk -q "$F" <<EOF
label: gpt
first-lba: 2048
start=2048, size=$((100*2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition"
start=$((2048+100*2048)), size=$((16*2048)), type=E3C9E316-0B5C-4DB8-817D-F92DF00215AE, name="Microsoft reserved partition"
start=$((2048+116*2048)), size=$((20*1024*2048)), type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="Basic data partition"
start=$(( SIZE*1024*2048 - 2048 - 600*2048 )), size=$((600*2048)), type=DE94BBA4-06D1-4D40-A16A-BFD50179D6AC, name="Basic data partition"
EOF
# one loop device per partition, by offset: partition nodes made after a container starts do not appear in it
# loop device nodes beyond the ones the container started with
for i in $(seq 0 127); do [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i; done
part() { sfdisk -J "$F" | python3 -c "import json,sys; p=json.load(sys.stdin)['partitiontable']['partitions'][$1-1]; print(p['start']*512, p['size']*512)"; }
attach() { set -- $(part $1); losetup -f --show -o $1 --sizelimit $2 "$F"; }
P1=$(attach 1); P3=$(attach 3); P4=$(attach 4)
trap 'umount /mnt/w 2>/dev/null || true; losetup -d $P1 $P3 $P4' EXIT
mkfs.vfat -F 32 -n SYSTEM $P1 >/dev/null
mkntfs -Q -F -L Windows $P3 >/dev/null
mkntfs -Q -F -L Recovery $P4 >/dev/null
W=$(mktemp -d)
cat > $W/standin.cfg <<'EOF'
echo "Windows Boot Manager stand-in (test disk, not Windows)."
echo "The menu entry chainloaded EFI/Microsoft/Boot/bootmgfw.efi from the shared EFI system partition."
sleep 600
EOF
grub-mkstandalone -O x86_64-efi -o $W/bootmgfw.efi --modules="echo sleep" "boot/grub/grub.cfg=$W/standin.cfg" 2>/dev/null
mkdir -p /mnt/w
mount $P1 /mnt/w
mkdir -p /mnt/w/EFI/Microsoft/Boot /mnt/w/EFI/Boot
cp $W/bootmgfw.efi /mnt/w/EFI/Microsoft/Boot/bootmgfw.efi
cp $W/bootmgfw.efi /mnt/w/EFI/Boot/bootx64.efi
: > /mnt/w/EFI/Microsoft/Boot/BCD
umount /mnt/w
mount -t ntfs3 $P3 /mnt/w 2>/dev/null || mount -t ntfs-3g $P3 /mnt/w
mkdir -p "/mnt/w/Windows/System32" "/mnt/w/Users/Lutz/Documents" "/mnt/w/Program Files"
printf 'Hallo Welt, von Windows aus geschrieben (Testdatei).\r\n' > "/mnt/w/Users/Lutz/Documents/Hallo Welt.txt"
umount /mnt/w
sfdisk -l "$F"
