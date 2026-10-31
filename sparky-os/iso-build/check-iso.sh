#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/31
# Checks a packed ISO against the recipe: the live kernel is the edition's and the only one (/live and the image's /boot),
# the boot menus have no second kernel and offer the Secure Boot enrolment, the EFI image carries Debian's signed shim,
# GRUB and MokManager (the same files as the root file system's packages) and the edition's certificate, the edition's
# kernel is signed with that certificate's key, the default boot splash is the Stereo one (in the image and in the live
# boot image), command-not-found's index is filled, and every kernel the ISO boots or installs carries the security
# fixes kernel-fixes.py lists, with no older kernel left (the ISO's kernels, initrds and menus; the image's /boot,
# module trees, DKMS builds and kernel packages, linux-libc-dev included). Runs as root in the build image (privileged,
# for the loop mounts and the chroot), with the root file system at /rootfs and the build tree at /build. The ISO and
# its filesystem.squashfs are mounted read-only and only a few small files are copied out, into the container's own
# /tmp. Prints a report; exits 1 on any failed check.
#   check-iso.sh ISO [CERT.der]
set -u
ISO=$1; CERT=${2:-/rootfs/usr/lib/sparkybackup/stereo/secureboot/sparky-stereo-secureboot-2026.der}
T=$(mktemp -d)
I=$T/iso
mkdir -p "$I" /rootfs/tmp/check-iso
for i in $(seq 0 63); do [ -e /dev/loop$i ] || mknod /dev/loop$i b 7 $i; done
mount -o loop,ro "$ISO" "$I" || { echo "FAIL  cannot mount $ISO"; exit 1; }
mount --bind -o ro "$I/live" /rootfs/tmp/check-iso
trap 'mountpoint -q "$T/image" && umount "$T/image"; umount /rootfs/tmp/check-iso; rmdir /rootfs/tmp/check-iso; umount "$I"; rm -rf "$T"' EXIT
fails=0
ok() { echo "PASS  $*"; }
no() { echo "FAIL  $*"; fails=$((fails + 1)); }
x() { cp "$I/$1" "$T/$2" 2>/dev/null; }

echo "== $(basename "$ISO") $(stat -c %s "$ISO") bytes"
echo "-- /live and /EFI/boot on the ISO"
(cd "$I" && ls -l live EFI/boot) | sed "s/^/   /"
ls "$I/live" | grep -q "vmlinuz2\|initrd2" && no "/live has a second kernel" || ok "/live has one kernel"
for f in live/vmlinuz boot/grub/grub.cfg isolinux/isolinux.cfg boot/grub/efi.img .disk/info; do
	x "$f" "$(echo "$f" | tr / _)" || no "/$f missing"
done
KV=$(chroot /rootfs dpkg-query -W -f '${Depends}' linux-image-sparky-stereo | sed -n 's/^linux-image-\([^ ,]*\).*/\1/p')
cmp -s "$T/live_vmlinuz" "/rootfs/boot/vmlinuz-$KV" && ok "/live/vmlinuz is the edition's $KV" || no "/live/vmlinuz is not /boot/vmlinuz-$KV"
echo "   .disk/info: $(cat "$T/.disk_info")"

echo "-- menus"
grep -q 'vmlinuz2\|initrd2' "$T/boot_grub_grub.cfg" "$T/isolinux_isolinux.cfg" && no "a menu names a second kernel" || ok "no menu names a second kernel"
grep -q 'nokaslr' "$T/boot_grub_grub.cfg" && no "GRUB's menu still adds nokaslr" || ok "no nokaslr (the edition's kernel keeps KASLR on 32-bit UEFI)"
grep -q 'menuentry "Secure Boot: enroll the Sparky Stereo OS key" --id sparky-enroll' "$T/boot_grub_grub.cfg" && grep -q 'chainloader /EFI/boot/mmx64.efi' "$T/boot_grub_grub.cfg" \
	&& ok "the enrolment entry starts /EFI/boot/mmx64.efi" || no "no enrolment entry"
n=$(grep -c 'sparky_no_key$' "$T/boot_grub_grub.cfg"); l=$(grep -c 'if linux /live/vmlinuz' "$T/boot_grub_grub.cfg")
[ "$n" = "$l" ] && ok "every live entry ($l) leads to the explanation when shim refuses the kernel" || no "$n of $l live entries lead to the explanation"
for lang in English Polski Português Français Deutsch 日本語 한국어 简体中文 繁體中文; do
	[ "$(grep -c "echo \"$lang: " "$T/boot_grub_grub.cfg")" = 2 ] || no "the two texts are not both in $lang"
done && ok "both texts in the nine required languages"

echo "-- EFI image (efi.img)"
mdir -/ -b -i "$T/boot_grub_efi.img" :: 2>/dev/null | sed "s/^/   /"
for f in bootx64.efi:usr/lib/shim/shimx64.efi.signed mmx64.efi:usr/lib/shim/mmx64.efi.signed grubx64.efi:usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed; do
	e=${f%%:*}; src=/rootfs/${f#*:}
	mcopy -n -i "$T/boot_grub_efi.img" "::EFI/boot/$e" "$T/$e" 2>/dev/null || { no "efi.img has no EFI/boot/$e"; continue; }
	cmp -s "$T/$e" "$src" && ok "EFI/boot/$e is $src ($(sha256sum "$T/$e" | cut -c1-16))" || no "EFI/boot/$e differs from $src"
done
echo "   $(chroot /rootfs dpkg-query -W -f '${Package} ${Version}\n' shim-signed grub-efi-amd64-signed | tr '\n' ' ')"
if mcopy -n -i "$T/boot_grub_efi.img" ::EFI/boot/sparky-stereo-secureboot-2026.der "$T/cert.der" 2>/dev/null; then
	cmp -s "$T/cert.der" "$CERT" && ok "EFI/boot/sparky-stereo-secureboot-2026.der is $CERT (sha256 $(sha256sum "$CERT" | cut -c1-64))" \
		|| no "the EFI image's certificate differs from $CERT"
else
	no "efi.img has no EFI/boot/sparky-stereo-secureboot-2026.der"
fi
{ echo "-----BEGIN CERTIFICATE-----"; base64 -w64 "$CERT"; echo "-----END CERTIFICATE-----"; } > "$T/cert.pem"
sbverify --list "$T/bootx64.efi" 2>/dev/null | grep -E "subject:" | sed "s/^/   shim: /"
sbverify --list "$T/grubx64.efi" 2>/dev/null | grep -E "subject:" | sed "s/^/   GRUB: /"
sbverify --list "$T/live_vmlinuz" 2>/dev/null | grep -E "subject:" | sed "s/^/   kernel: /"
sbverify --cert "$T/cert.pem" "$T/live_vmlinuz" >/dev/null 2>&1 && ok "the live kernel's signature verifies with the certificate" \
	|| no "the live kernel is not signed with the certificate's key"

echo "-- the image (filesystem.squashfs)"
unsquashfs -n -d "$T/sq" "$I/live/filesystem.squashfs" var/lib/dpkg/status etc/plymouth/plymouthd.conf \
	usr/share/plymouth/plymouthd.defaults var/lib/command-not-found/commands.db >/dev/null 2>&1
# /boot by name only (its boot image is hundreds of MB): empty files of the same names for boot-kernels.py
mkdir -p "$T/sq/boot"
unsquashfs -n -lc "$I/live/filesystem.squashfs" boot 2>/dev/null | sed -n 's|^squashfs-root/boot/\([^/]*\)$|\1|p' | while read -r f; do : > "$T/sq/boot/$f"; done
python3 /build/boot-kernels.py "$T/sq" && ok "the image's /boot and packages hold only the edition's kernel" || no "the image holds a kernel that is not the edition's"
# the default splash as Plymouth's own plymouth-set-default-theme reads it (get_default_theme): plymouthd.conf's Theme,
# else plymouthd.defaults' (sparky-stereo-plymouth diverts it to name sparky-stereo-lines and clears package-written
# choices from plymouthd.conf)
t=$(sed -n 's/^Theme=//p' "$T/sq/etc/plymouth/plymouthd.conf" 2>/dev/null); w=plymouthd.conf
[ -n "$t" ] || { t=$(sed -n 's/^Theme=//p' "$T/sq/usr/share/plymouth/plymouthd.defaults" 2>/dev/null); w=plymouthd.defaults; }
[ "$t" = sparky-stereo-lines ] && ok "default boot splash: $t ($w)" || no "default boot splash: ${t:-none}"
chroot /rootfs lsinitramfs /tmp/check-iso/initrd.img 2>/dev/null | grep -E 'plymouth/themes/[^/]+/[^/]+\.plymouth$|plymouthd.conf' | sed "s/^/   initrd: /"
chroot /rootfs lsinitramfs /tmp/check-iso/initrd.img 2>/dev/null | grep -q 'plymouth/themes/sparky-stereo-lines/sparky-stereo-lines.script' \
	&& ok "the live boot image carries sparky-stereo-lines" || no "the live boot image lacks sparky-stereo-lines"
db=$T/sq/var/lib/command-not-found/commands.db
if [ -s "$db" ]; then
	python3 - "$db" <<'PY' || fails=$((fails + 1))
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
n = c.execute('select count(*) from commands').fetchone()[0]
print('   command-not-found: %d commands, %d packages' % (n, c.execute('select count(*) from packages').fetchone()[0]))
bad = 0
for cmd in ('align_image_stack', 'vlc-stereo', 'stereo-create'):
    r = [x[0] for x in c.execute('select p.name from commands m join packages p using(pkgID) where m.command=?', (cmd,))]
    print('%s  command-not-found names %s -> %s' % ('PASS' if r else 'FAIL', cmd, r))
    bad += not r
sys.exit(1 if bad or n < 1000 else 0)
PY
else
	no "command-not-found's index is empty"
fi

echo "-- the kernels and their security fixes (kernel-fixes.py, the image mounted read-only)"
mkdir -p "$T/image"
if mount -o loop,ro "$I/live/filesystem.squashfs" "$T/image"; then
	python3 /build/kernel-fixes.py "$I" "$T/image" > "$T/kernel-fixes.txt" 2>&1; r=$?
	cat "$T/kernel-fixes.txt"
	if [ $r != 0 ]; then
		n=$(grep -c '^FAIL' "$T/kernel-fixes.txt"); [ "$n" -gt 0 ] || { n=1; echo "FAIL  kernel-fixes.py stopped (exit $r)"; }
		fails=$((fails + n))
	fi
	umount "$T/image"
else
	no "cannot mount the image's filesystem.squashfs"
fi
echo "== $( [ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ $fails = 0 ]
