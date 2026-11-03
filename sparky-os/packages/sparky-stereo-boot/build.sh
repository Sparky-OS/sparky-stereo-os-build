#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
#
# Builds the sparky-stereo-boot package (hand assembled, Paweł's formula).
#   build.sh OUTDIR
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
PKG=sparky-stereo-boot
VERSION=0.1.7+lc1
umask 022
mkdir -p "$OUT"
D=$(mktemp -d "${TMPDIR:-/tmp}/stereo-boot-build.XXXXXX")
trap 'rm -rf "$D"' EXIT
chmod 755 "$D"
install -D -m 755 "$HERE/bin/sparky-stereo-boot" "$D/usr/bin/sparky-stereo-boot"
for u in sparky-stereo-boot.socket sparky-stereo-boot@.service sparky-stereo-boot-handover.service sparky-stereo-boot-check.service; do
	install -D -m 644 "$HERE/systemd/system/$u" "$D/usr/lib/systemd/system/$u"
done
install -D -m 644 "$HERE/systemd/system/plymouth-quit.service.d/sparky-stereo-boot.conf" "$D/usr/lib/systemd/system/plymouth-quit.service.d/sparky-stereo-boot.conf"
install -D -m 644 "$HERE/systemd/system/sddm.service.d/sparky-stereo-boot.conf" "$D/usr/lib/systemd/system/sddm.service.d/sparky-stereo-boot.conf"
mkdir -p "$D/usr/lib/systemd/system/sockets.target.wants" "$D/usr/lib/systemd/system/multi-user.target.wants" \
	"$D/usr/lib/systemd/user/default.target.wants" "$D/usr/lib/systemd/catalog"
ln -s ../sparky-stereo-boot.socket "$D/usr/lib/systemd/system/sockets.target.wants/sparky-stereo-boot.socket"
ln -s ../sparky-stereo-boot-check.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-boot-check.service"
for u in sparky-stereo-boot-export.path sparky-stereo-boot-export.service; do
	install -D -m 644 "$HERE/systemd/user/$u" "$D/usr/lib/systemd/user/$u"
	ln -s ../$u "$D/usr/lib/systemd/user/default.target.wants/$u"
done
# the boot's messages, word for word, as journal catalogs: the edition's one engine keeps the boot's problems and its
# session notifier shows them (0.1.6, ORDER 350)
sparky-stereo-problems catalog sparky-stereo-boot "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL19
install -D -m 644 "$HERE/default/sparky-stereo-boot" "$D/etc/default/sparky-stereo-boot"
install -D -m 755 "$HERE/initramfs/sparky-stereo-nvidia" "$D/usr/share/initramfs-tools/hooks/sparky-stereo-nvidia"
install -D -m 644 "$HERE/modprobe/sparky-stereo-nvidia-kms.conf" "$D/usr/lib/modprobe.d/sparky-stereo-nvidia-kms.conf"
install -D -m 644 "$HERE/grub/30-sparky-stereo-boot.cfg" "$D/etc/default/grub.d/30-sparky-stereo-boot.cfg"
install -D -m 644 "$HERE/grub/31-sparky-stereo-ia32.cfg" "$D/etc/default/grub.d/31-sparky-stereo-ia32.cfg"
# Secure Boot: the edition's public certificate, kept next to every shim on the EFI system partition, and the GRUB
# entry that enrolls it with MokManager (lib/secureboot.py)
install -D -m 644 "$HERE/../../secureboot/sparky-stereo-secureboot-2026.der" "$D/usr/share/sparky-stereo-boot/secureboot/sparky-stereo-secureboot-2026.der"
install -D -m 644 "$HERE/lib/secureboot.py" "$D/usr/lib/sparky-stereo-boot/secureboot.py"
# what failed, why and what to do, kept until it is repaired (0.1.5)
install -D -m 644 "$HERE/lib/problems.py" "$D/usr/lib/sparky-stereo-boot/problems.py"
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
# The maintainer scripts tell what failed, why and what to do; problems.py keeps it for repair. Each step either fails
# the package, as grub2's own postinst does when update-grub fails (Debian Policy 6.4: a nonzero exit status for
# failure), or is said, kept and the package configures, as debhelper's own service starts do (deb-systemd-invoke
# start ... || true) and shim-signed does for grub-install, where the boot of this system does not depend on it.
cat > "$D/DEBIAN/postinst" <<'SCRIPT'
#!/bin/sh
set -e
P=/usr/lib/sparky-stereo-boot/problems.py
if [ "$1" = configure ]; then
	failed=
	# 0.1.5 kept its problems in its own store: they move into the engine once, keeping when each was found. One that
	# cannot move stays there and is said, and kept as the problem old-store, so the person's next login tells it and
	# repair tries again; the package configures
	if [ -n "$2" ] && dpkg --compare-versions "$2" lt 0.1.6 && [ -d /var/lib/sparky-stereo-boot/problems ]; then
		python3 $P migrate /var/lib/sparky-stereo-boot/problems || :
	fi
	if [ -d /run/systemd/system ]; then
		# said and kept; the package configures (the boot itself does not need them)
		python3 $P run systemd-reload LOCAL60 -- systemctl daemon-reload || :
		for u in sparky-stereo-boot.socket:LOCAL22 sparky-stereo-kernel-keep.path:LOCAL59; do
			if [ "$(systemctl is-enabled "${u%:*}" 2>/dev/null || :)" = masked ]; then
				python3 $P say LOCAL55 "${u%:*}" "${u%:*}"   # the system's own choice
			else
				python3 $P run "start-${u%:*}" "${u#*:}" -- systemctl start "${u%:*}" || :
			fi
		done
	fi
	# the Sparky Stereo OS certificate next to every shim on the EFI system partition: a failure is said and kept by
	# secureboot.py, and the package configures (this system boots without it until Secure Boot needs the key)
	python3 /usr/lib/sparky-stereo-boot/secureboot.py esp || :
	# the kernel line takes ${sparky_stereo_boot} from GRUB's environment block (0.1.0), the menu the Secure Boot
	# enrolment entry (0.1.3), 30-sparky-stereo-boot.cfg says what GRUB is given and keeps it (0.1.5), and the menu's
	# text has one size for every screen (0.1.7); a failed update-grub fails the package, as grub2's postinst does
	if { [ -z "$2" ] || dpkg --compare-versions "$2" lt 0.1.7; } && [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then
		python3 $P run update-grub LOCAL21 -- update-grub || failed=1
	fi
	[ -z "$failed" ] || exit 1
fi
if [ "$1" = triggered ]; then
	# shim's or GRUB's signed programs were installed again: the certificate beside them again (said and kept by
	# secureboot.py when it cannot be placed)
	python3 /usr/lib/sparky-stereo-boot/secureboot.py esp || :
fi
exit 0
SCRIPT
# postrm runs after the package's files are gone: its messages are written into it here, from the language files
messages() {
	for l in "$HERE"/lang/*; do
		code=$(basename "$l")
		printf '\t%s)\n\t\tcase $1 in\n' "$code"
		for k in 56 57 58; do
			printf '\t\t%s) f=%s ;;\n' "$k" "$(sed -n "s/^LOCAL$k=\(\".*\"\)\$/\1/p" "$l")"
		done
		printf '\t\tesac ;;\n'
	done
}
{
cat <<'SCRIPT'
#!/bin/sh
set -e
# the messages in the system's language (the package's language files are gone by now)
say() {
	f=
	case $lang in
SCRIPT
messages
cat <<'SCRIPT'
	esac
	k=$1; shift
	# shellcheck disable=SC2059
	printf "sparky-stereo-boot: $f\n" "$@" >&2
	if [ "$lang" != en ]; then lang_was=$lang; lang=en; say "$k" "$@"; lang=$lang_was; fi
}
lang=${LANG:-}
[ -n "$lang" ] || lang=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"' | head -n 1)
lang=${lang%%.*}
case $lang in
pt_BR|zh_CN|zh_TW) ;;
zh*) lang=zh_CN ;;
*) lang=${lang%%_*}; case $lang in pl|fr|de|ja|ko) ;; *) lang=en ;; esac ;;
esac
failed=0
# STEP COMMAND...: a step whose failure leaves the next boot with what the package set up fails the removal (no
# error unwind, the package stays half-installed and the removal can run again, Debian Policy 6.7), as Debian's
# own kernel hooks fail a kernel's removal when update-grub fails
must() { if "$@"; then :; else rc=$?; say 56 "$*" "$rc"; say 57; failed=1; fi; }
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
		must grub-editenv /boot/grub/grubenv unset sparky_stereo_boot
	fi
	must rm -f /etc/sddm.conf.d/50-sparky-stereo-boot.conf
	# said; the next boot reloads systemd anyway
	if [ -d /run/systemd/system ]; then systemctl daemon-reload || say 56 "systemctl daemon-reload" "$?"; fi
	# the NVIDIA modules leave the boot images with the hook, every kernel's (initramfs-tools' own update_initramfs is
	# back by now, and its default rebuilds only the newest); without update-initramfs the boot images are another
	# generator's, as Debian's initramfs-tools hook leaves them
	if command -v update-initramfs >/dev/null; then must update-initramfs -u -k all; fi
	# a problem of a package that is gone cannot be repaired by it (ORDER 350): the engine lets go of the boot's
	if command -v sparky-stereo-problems >/dev/null; then must sparky-stereo-problems clear --all sparky-stereo-boot; fi
	;;
purge)
	must rm -rf /var/lib/sparky-stereo-boot
	# said; a certificate left on the partition does not change any boot
	for f in /boot/efi/EFI/*/sparky-stereo-secureboot-2026.der; do
		[ -e "$f" ] || continue
		rm -f "$f" || say 58 "$f"
	done
	if [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then must update-grub; fi
	;;
esac
exit $failed
SCRIPT
} > "$D/DEBIAN/postrm"
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
Depends: grub-common, libdrm2, python3, systemd, sparky-stereo-problems (>= 0.1.0)
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
  .
  Nothing in the boot's upkeep fails silently: a failed update-grub,
  boot image, Secure Boot certificate, kernel cleanup or 3D splash
  hand-over says what failed, why and what to do, in the system's
  language, and is kept with its output until it is repaired;
  sparky-stereo-boot status lists it and the session shows it.
CONTROL
(cd "$D" && find usr etc -type f -exec md5sum {} + | grep -v ' etc/' | sort -k2) > "$D/DEBIAN/md5sums"
chmod 644 "$D/DEBIAN/control" "$D/DEBIAN/md5sums" "$D/DEBIAN/conffiles"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone \
    "$D" "$OUT" --authoring "$HERE"
