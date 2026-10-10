#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Guest only, as root, in a disposable VM: create what the installer must
# create for Hibernate with the Cushion Swap File, or remove it again.
#   guest-hibernate-setup.sh [AREA]     a swap file at least the size of RAM,
#       its noauto line in /etc/fstab (off at boot), resume= and
#       resume_offset= on the kernel command line, RESUME= in the initramfs
#   guest-hibernate-setup.sh --undo [AREA]
# On Btrfs the file comes from "btrfs filesystem mkswapfile" (no copy on
# write) and the offset from "btrfs inspect-internal map-swapfile -r".
set -eu
undo=0
[[ ${1:-} == --undo ]] && { undo=1; shift; }
area=${1:-/swapfile}
grub=/etc/default/grub.d/sparky-stereo-resume.cfg
initramfs=/etc/initramfs-tools/conf.d/resume
if ((undo)); then
	swapoff "$area" 2>/dev/null || true
	sed -i "\|^$area none swap noauto|d" /etc/fstab
	rm -f "$area" "$grub" "$initramfs"
	update-initramfs -u >/dev/null
	update-grub >/dev/null 2>&1
	echo "removed"
	exit 0
fi
ram_mib=$(awk '$1 == "MemTotal:" { print int(($2 + 1023) / 1024) }' /proc/meminfo)
size_mib=$(((ram_mib + 1023) / 1024 * 1024))
filesystem=$(findmnt -n -o FSTYPE -T "$(dirname "$area")")
if [[ ! -e $area ]]; then
	if [[ $filesystem == btrfs ]]; then
		btrfs filesystem mkswapfile --size "${size_mib}m" "$area" >/dev/null
	else
		fallocate -l "${size_mib}M" "$area"
		chmod 600 "$area"
		mkswap -q "$area"
	fi
fi
grep -q "^$area none swap noauto" /etc/fstab || echo "$area none swap noauto 0 0" >>/etc/fstab
uuid=$(findmnt -n -o UUID -T "$area")
if [[ $filesystem == btrfs ]]; then
	offset=$(btrfs inspect-internal map-swapfile -r "$area")
else
	offset=$(filefrag -v -b4096 "$area" | awk '$1 == "0:" { sub(/\.\..*/, "", $4); print $4; exit }')
fi
echo "RESUME=UUID=$uuid" >"$initramfs"
mkdir -p "$(dirname "$grub")"
printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT resume=UUID=%s resume_offset=%s"\n' "$uuid" "$offset" >"$grub"
update-initramfs -u >/dev/null
update-grub >/dev/null 2>&1
echo "area=$area size_mib=$size_mib file_system=$filesystem resume=UUID=$uuid resume_offset=$offset"
