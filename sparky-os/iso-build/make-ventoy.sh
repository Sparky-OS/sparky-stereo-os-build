#!/bin/sh
# Writes a stick image the way a person does it with Ventoy's Linux tool: Ventoy2Disk.sh installs Ventoy (with
# Secure Boot support, -s) on the "stick", then the ISO file is copied onto its exFAT data partition.
# The stick is an image file on a loop device. Runs as root in beta-iso-lutz-build:1, privileged and with the
# host's /dev (Ventoy formats the partitions it has just made, whose device nodes appear there only).
# Usage: make-ventoy.sh VENTOY_DIR STICK.raw SIZE_GIB ISO
set -eu
V=$1; F=$2; SIZE=$3; ISO=$4
rm -f "$F"; truncate -s ${SIZE}G "$F"
L=$(losetup -f --show -P "$F")
trap 'umount /mnt/v 2>/dev/null || true; losetup -d "$L"' EXIT
# the loop device must be backed by this file, nothing else is touched
[ "$(losetup -n -O BACK-FILE "$L" | sed 's/ (deleted)//')" = "$(readlink -f "$F")" ] || { echo "make-ventoy: $L is not $F" >&2; exit 1; }
echo "== Ventoy $(cat "$V/ventoy/version" 2>/dev/null) on $L ($F)"
cd "$V"
printf 'y\ny\n' | sh ./Ventoy2Disk.sh -i -s "$L"
partprobe "$L" 2>/dev/null || true; sleep 2
lsblk -o NAME,SIZE,FSTYPE,LABEL "$L"
mkdir -p /mnt/v
mount "${L}p1" /mnt/v
cp "$ISO" /mnt/v/
sync
ls -la /mnt/v
umount /mnt/v
