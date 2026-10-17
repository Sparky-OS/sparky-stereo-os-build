#!/bin/sh
# A FAT test disk with GRUB 2.14 for 32-bit UEFI (Debian's grub-efi-ia32-bin) as EFI/BOOT/BOOTIA32.EFI,
# a standalone image whose own configuration starts the stick's menu from the CD. Runs in debian:testing.
set -eu
apt-get -qq update >/dev/null && apt-get -qq install -y --no-install-recommends grub-efi-ia32-bin grub-common dosfstools mtools >/dev/null
dpkg-query -W grub-efi-ia32-bin
cat > /tmp/embedded.cfg <<'CFG'
search --no-floppy --set=root --file /.disk/info
configfile ($root)/boot/grub/grub.cfg
CFG
grub-mkstandalone -O i386-efi -o /o/BOOTIA32.EFI --locales= --themes= "boot/grub/grub.cfg=/tmp/embedded.cfg"
ls -la /o/BOOTIA32.EFI
rm -f /o/ia32-grub214.img
mkfs.msdos -C /o/ia32-grub214.img 32768 >/dev/null
mmd -i /o/ia32-grub214.img ::EFI ::EFI/BOOT
mcopy -i /o/ia32-grub214.img /o/BOOTIA32.EFI ::EFI/BOOT/BOOTIA32.EFI
chown 1000:1000 /o/*
