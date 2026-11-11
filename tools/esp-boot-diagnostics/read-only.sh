#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/11
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/11
# Read-only kit; run as root to include the complete system journal.
set -u
printf '\nFstab\n'
cat /etc/fstab
printf '\nMount state\n'
findmnt /boot/efi || :
findmnt -T /tmp
lsblk -o NAME,MAJ:MIN,FSTYPE,UUID,MOUNTPOINTS
printf '\nUnits and dependency state\n'
systemctl show boot-efi.mount tmp.mount local-fs.target sysinit.target \
	-p Id -p FragmentPath -p SourcePath -p DropInPaths -p LoadState \
	-p ActiveState -p SubState -p Requires -p Wants -p RequiredBy -p WantedBy \
	-p After -p Before -p Result -p ConditionResult -p AssertResult \
	-p ActiveEnterTimestampMonotonic -p InactiveEnterTimestampMonotonic
systemctl cat boot-efi.mount tmp.mount local-fs.target sysinit.target || :
systemctl list-dependencies --all local-fs.target
printf '\nGenerated units\n'
for unit in boot-efi.mount tmp.mount; do
	for dir in /run/systemd/generator.early /run/systemd/generator /run/systemd/generator.late; do
		if test -f "$dir/$unit"; then
			printf '\n%s\n' "$dir/$unit"
			cat "$dir/$unit"
		fi
	done
done
printf '\nCurrent boot journal, mount and transaction messages\n'
journalctl -b --no-pager -o short-monotonic \
	-g 'boot-efi|tmp.mount|local-fs|systemd-fsck|masked|ordering cycle|dependency job|Dependency failed|ESP|EFI system partition'
