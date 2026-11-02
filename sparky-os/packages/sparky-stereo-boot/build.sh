#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/30
#
# Builds the sparky-stereo-boot package (hand assembled, Paweł's formula).
#   build.sh OUTDIR
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
PKG=sparky-stereo-boot
VERSION=0.1.4+lc1
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
# Secure Boot: the edition's public certificate, kept next to every shim on the EFI system partition, and the GRUB
# entry that enrolls it with MokManager (lib/secureboot.py)
install -D -m 644 "$HERE/../../secureboot/sparky-stereo-secureboot-2026.der" "$D/usr/share/sparky-stereo-boot/secureboot/sparky-stereo-secureboot-2026.der"
install -D -m 644 "$HERE/lib/secureboot.py" "$D/usr/lib/sparky-stereo-boot/secureboot.py"
install -D -m 755 "$HERE/grub/35_sparky_stereo_secureboot" "$D/etc/grub.d/35_sparky_stereo_secureboot"
install -D -m 755 "$HERE/kernel/zz-sparky-stereo-secureboot" "$D/etc/kernel/postinst.d/zz-sparky-stereo-secureboot"
# two kernels per flavour (0.1.4): the kernel hook records an install, the service waits for apt and dpkg and purges
install -D -m 755 "$HERE/lib/kernel-keep.py" "$D/usr/lib/sparky-stereo-boot/kernel-keep.py"
install -D -m 755 "$HERE/kernel/zz-sparky-stereo-kernel-keep" "$D/etc/kernel/postinst.d/zz-sparky-stereo-kernel-keep"
for u in sparky-stereo-kernel-keep.path sparky-stereo-kernel-keep.service; do
	install -D -m 644 "$HERE/systemd/system/$u" "$D/usr/lib/systemd/system/$u"
done
mkdir -p "$D/usr/lib/systemd/system/paths.target.wants"
ln -s ../sparky-stereo-kernel-keep.path "$D/usr/lib/systemd/system/paths.target.wants/sparky-stereo-kernel-keep.path"
# every update-initramfs -u writes every kernel's boot image (0.1.4): initramfs-tools' update-initramfs.conf is
# diverted to .debian (preinst) and its name becomes a link to the edition's file, a conffile of this package beside it
# (a diverted conffile at the same name could not be renamed back on removal, as dpkg keeps conffiles then)
install -D -m 644 "$HERE/initramfs-tools/update-initramfs.conf" "$D/etc/initramfs-tools/update-initramfs.conf.sparky-stereo"
ln -s update-initramfs.conf.sparky-stereo "$D/etc/initramfs-tools/update-initramfs.conf"
for l in "$HERE"/lang/*; do
	install -D -m 644 "$l" "$D/usr/share/sparky/sparky-stereo-boot/$(basename "$l")"
done
install -D -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
install -D -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
mkdir -p "$D/DEBIAN"
printf '%s\n' /etc/default/sparky-stereo-boot /etc/default/grub.d/30-sparky-stereo-boot.cfg /etc/default/grub.d/31-sparky-stereo-ia32.cfg \
	/etc/grub.d/35_sparky_stereo_secureboot /etc/kernel/postinst.d/zz-sparky-stereo-secureboot \
	/etc/kernel/postinst.d/zz-sparky-stereo-kernel-keep /etc/initramfs-tools/update-initramfs.conf.sparky-stereo > "$D/DEBIAN/conffiles"
cat > "$D/DEBIAN/preinst" <<'SCRIPT'
#!/bin/sh
# initramfs-tools' update-initramfs.conf moves aside for the edition's (update_initramfs=all)
set -e
if [ "$1" = install ] || [ "$1" = upgrade ]; then
	dpkg-divert --package sparky-stereo-boot --add --rename \
		--divert /etc/initramfs-tools/update-initramfs.conf.debian /etc/initramfs-tools/update-initramfs.conf >/dev/null
fi
exit 0
SCRIPT
cat > "$D/DEBIAN/postinst" <<'SCRIPT'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
		systemctl start sparky-stereo-boot.socket || true
		systemctl start sparky-stereo-kernel-keep.path || true
	fi
	# the Sparky Stereo OS certificate next to every shim on the EFI system partition
	python3 /usr/lib/sparky-stereo-boot/secureboot.py esp || true
	# the kernel line takes ${sparky_stereo_boot} from GRUB's environment block (0.1.0), and the menu the Secure Boot
	# enrolment entry (0.1.3)
	if { [ -z "$2" ] || dpkg --compare-versions "$2" lt 0.1.3; } && [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then
		update-grub || true
	fi
fi
if [ "$1" = triggered ]; then
	# shim's or GRUB's signed programs were installed again: the certificate beside them again
	python3 /usr/lib/sparky-stereo-boot/secureboot.py esp || true
fi
SCRIPT
cat > "$D/DEBIAN/postrm" <<'SCRIPT'
#!/bin/sh
set -e
case "$1" in
remove|abort-install|abort-upgrade)
	# initramfs-tools' update-initramfs.conf comes back (the edition's link is gone with the package's files on removal)
	if [ "$1" = remove ] || [ -z "$2" ] || dpkg --compare-versions "$2" lt 0.1.4; then
		if [ "$(readlink /etc/initramfs-tools/update-initramfs.conf)" = update-initramfs.conf.sparky-stereo ]; then
			rm -f /etc/initramfs-tools/update-initramfs.conf
		fi
		dpkg-divert --package sparky-stereo-boot --remove --rename \
			--divert /etc/initramfs-tools/update-initramfs.conf.debian /etc/initramfs-tools/update-initramfs.conf >/dev/null
	fi
	;;
esac
case "$1" in
remove)
	if [ -f /boot/grub/grubenv ] && command -v grub-editenv >/dev/null; then
		grub-editenv /boot/grub/grubenv unset sparky_stereo_boot || true
	fi
	rm -f /etc/sddm.conf.d/50-sparky-stereo-boot.conf
	if [ -d /run/systemd/system ]; then systemctl daemon-reload || true; fi
	# the NVIDIA modules leave the boot images with the hook, every kernel's (initramfs-tools' own update_initramfs is
	# back by now, and its default rebuilds only the newest)
	if command -v update-initramfs >/dev/null; then update-initramfs -u -k all || true; fi
	;;
purge)
	rm -rf /var/lib/sparky-stereo-boot
	rm -f /boot/efi/EFI/*/sparky-stereo-secureboot-2026.der 2>/dev/null || true
	if [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then update-grub || true; fi
	;;
esac
SCRIPT
chmod 755 "$D/DEBIAN/preinst" "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
# the boot image takes the NVIDIA hook and its options at the next initramfs-tools run
printf 'activate-noawait update-initramfs\ninterest-noawait /usr/lib/shim\ninterest-noawait /usr/lib/grub/x86_64-efi-signed\n' > "$D/DEBIAN/triggers"
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
  .
  It keeps two kernels per flavour, the running one and one more, and
  removes the older ones after a new kernel has installed; every boot
  image is written again whenever the boot changes, the older kernel's
  too.
CONTROL
(cd "$D" && find usr etc -type f -exec md5sum {} + | grep -v ' etc/' | sort -k2) > "$D/DEBIAN/md5sums"
chmod 644 "$D/DEBIAN/control" "$D/DEBIAN/md5sums" "$D/DEBIAN/conffiles"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone \
    "$D" "$OUT" --authoring "$HERE"
