#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
#
# Builds the sparky-stereo-boot package (hand assembled, Paweł's formula).
#   build.sh OUTDIR
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
PKG=sparky-stereo-boot
VERSION=0.1.1+lc1
umask 022
mkdir -p "$OUT"
D=$(mktemp -d "${TMPDIR:-/tmp}/stereo-boot-build.XXXXXX")
trap 'rm -rf "$D"' EXIT
chmod 755 "$D"
install -D -m 755 "$HERE/bin/sparky-stereo-boot" "$D/usr/bin/sparky-stereo-boot"
for u in sparky-stereo-boot.socket sparky-stereo-boot@.service sparky-stereo-boot-handover.service; do
	install -D -m 644 "$HERE/systemd/system/$u" "$D/usr/lib/systemd/system/$u"
done
install -D -m 644 "$HERE/systemd/system/plymouth-quit.service.d/sparky-stereo-boot.conf" "$D/usr/lib/systemd/system/plymouth-quit.service.d/sparky-stereo-boot.conf"
install -D -m 644 "$HERE/systemd/system/sddm.service.d/sparky-stereo-boot.conf" "$D/usr/lib/systemd/system/sddm.service.d/sparky-stereo-boot.conf"
mkdir -p "$D/usr/lib/systemd/system/sockets.target.wants" "$D/usr/lib/systemd/user/default.target.wants"
ln -s ../sparky-stereo-boot.socket "$D/usr/lib/systemd/system/sockets.target.wants/sparky-stereo-boot.socket"
for u in sparky-stereo-boot-export.path sparky-stereo-boot-export.service; do
	install -D -m 644 "$HERE/systemd/user/$u" "$D/usr/lib/systemd/user/$u"
	ln -s ../$u "$D/usr/lib/systemd/user/default.target.wants/$u"
done
install -D -m 644 "$HERE/default/sparky-stereo-boot" "$D/etc/default/sparky-stereo-boot"
install -D -m 755 "$HERE/initramfs/sparky-stereo-nvidia" "$D/usr/share/initramfs-tools/hooks/sparky-stereo-nvidia"
install -D -m 644 "$HERE/modprobe/sparky-stereo-nvidia-kms.conf" "$D/usr/lib/modprobe.d/sparky-stereo-nvidia-kms.conf"
install -D -m 644 "$HERE/grub/30-sparky-stereo-boot.cfg" "$D/etc/default/grub.d/30-sparky-stereo-boot.cfg"
install -D -m 644 "$HERE/grub/31-sparky-stereo-ia32.cfg" "$D/etc/default/grub.d/31-sparky-stereo-ia32.cfg"
for l in "$HERE"/lang/*; do
	install -D -m 644 "$l" "$D/usr/share/sparky/sparky-stereo-boot/$(basename "$l")"
done
install -D -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
install -D -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
mkdir -p "$D/DEBIAN"
printf '/etc/default/sparky-stereo-boot\n/etc/default/grub.d/30-sparky-stereo-boot.cfg\n/etc/default/grub.d/31-sparky-stereo-ia32.cfg\n' > "$D/DEBIAN/conffiles"
cat > "$D/DEBIAN/postinst" <<'SCRIPT'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
		systemctl start sparky-stereo-boot.socket || true
	fi
	# the kernel line takes ${sparky_stereo_boot} from GRUB's environment block from now on
	if [ -z "$2" ] && [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then
		update-grub || true
	fi
fi
SCRIPT
cat > "$D/DEBIAN/postrm" <<'SCRIPT'
#!/bin/sh
set -e
case "$1" in
remove)
	if [ -f /boot/grub/grubenv ] && command -v grub-editenv >/dev/null; then
		grub-editenv /boot/grub/grubenv unset sparky_stereo_boot || true
	fi
	rm -f /etc/sddm.conf.d/50-sparky-stereo-boot.conf
	if [ -d /run/systemd/system ]; then systemctl daemon-reload || true; fi
	# the NVIDIA modules leave the boot image with the hook
	if command -v update-initramfs >/dev/null; then update-initramfs -u || true; fi
	;;
purge)
	rm -rf /var/lib/sparky-stereo-boot
	if [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then update-grub || true; fi
	;;
esac
SCRIPT
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
# the boot image takes the NVIDIA hook and its options at the next initramfs-tools run
printf 'activate-noawait update-initramfs\n' > "$D/DEBIAN/triggers"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat > "$D/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: grub-common, libdrm2, python3, systemd
Recommends: plymouth (>= 26.134.222-1+stereo3d1), sparky-stereo-plymouth
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo OS boot that follows the main screen
  GRUB, the boot splash and the login screen follow the main screen as
  the person set it in the display settings: GRUB at its resolution, kept
  through the kernel, and the boot splash and the login screen in its 3D
  mode or stereo layout, handed over with no new mode set. The settings
  are read from the session whenever they change.
CONTROL
(cd "$D" && find usr etc -type f -exec md5sum {} + | grep -v ' etc/' | sort -k2) > "$D/DEBIAN/md5sums"
chmod 644 "$D/DEBIAN/control" "$D/DEBIAN/md5sums" "$D/DEBIAN/conffiles"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone \
    "$D" "$OUT" --authoring "$HERE"
