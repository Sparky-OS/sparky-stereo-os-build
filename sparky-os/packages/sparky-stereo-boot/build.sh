#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/25
#
# Builds the sparky-stereo-boot package (hand assembled, Paweł's formula).
#   build.sh OUTDIR
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
PKG=sparky-stereo-boot
VERSION=0.1.15+lc1
# the host's facts for the build record, and the source date from the recipe's last commit (ORDER 394b, ORDER 421b)
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "${SPARKY_BUILD_IMAGE:-plymouth-481-base:1}" "$HERE"
for ((i = 0; i < ${#SPARKY_PROV_ARGS[@]}; i++)); do
	[ "${SPARKY_PROV_ARGS[i]}" = -e ] && export "${SPARKY_PROV_ARGS[i + 1]}"
done
umask 022
mkdir -p "$OUT"
D=$(mktemp -d "${TMPDIR:-/tmp}/stereo-boot-build.XXXXXX")
trap 'rm -rf "$D"' EXIT
chmod 755 "$D"
install -D -m 755 "$HERE/bin/sparky-stereo-boot" "$D/usr/bin/sparky-stereo-boot"
for u in sparky-stereo-boot.socket sparky-stereo-boot@.service sparky-stereo-boot-handover.service sparky-stereo-boot-check.service \
	sparky-stereo-boot-login.service sparky-stereo-boot-finished.service \
	sparky-stereo-boot-secureboot.service sparky-stereo-boot-dkms-key.path; do
	install -D -m 644 "$HERE/systemd/system/$u" "$D/usr/lib/systemd/system/$u"
done
install -D -m 644 "$HERE/systemd/system/plymouth-quit.service.d/sparky-stereo-boot.conf" "$D/usr/lib/systemd/system/plymouth-quit.service.d/sparky-stereo-boot.conf"
install -D -m 644 "$HERE/systemd/system/sddm.service.d/sparky-stereo-boot.conf" "$D/usr/lib/systemd/system/sddm.service.d/sparky-stereo-boot.conf"
# the restart and shutdown splash with the main screen's choice saved now (0.1.12, ORDER 639): each of Plymouth's
# shutdown units starts plymouthd through sparky-stereo-boot plymouth-shutdown, with that unit's own mode
for u in reboot:reboot poweroff:shutdown halt:shutdown kexec:shutdown; do
	install -d "$D/usr/lib/systemd/system/plymouth-${u%%:*}.service.d"
	sed "s/@MODE@/${u#*:}/" "$HERE/systemd/system/plymouth-shutdown.service.d/sparky-stereo-boot.conf" \
		> "$D/usr/lib/systemd/system/plymouth-${u%%:*}.service.d/sparky-stereo-boot.conf"
	chmod 644 "$D/usr/lib/systemd/system/plymouth-${u%%:*}.service.d/sparky-stereo-boot.conf"
done
mkdir -p "$D/usr/lib/systemd/system/sockets.target.wants" "$D/usr/lib/systemd/system/multi-user.target.wants" \
	"$D/usr/lib/systemd/user/default.target.wants" "$D/usr/lib/systemd/catalog"
ln -s ../sparky-stereo-boot.socket "$D/usr/lib/systemd/system/sockets.target.wants/sparky-stereo-boot.socket"
ln -s ../sparky-stereo-boot-check.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-boot-check.service"
# after a start that did not finish (0.1.11, ORDER 572b): the login screen's service counts for systemd's
# boot-complete.target, and once that is reached (and after a resume from hibernation, as Debian's grub2-common.service)
# the start is recorded as finished wherever GRUB's flag is kept
mkdir -p "$D/usr/lib/systemd/system/boot-complete.target.requires"
ln -s ../sparky-stereo-boot-login.service "$D/usr/lib/systemd/system/boot-complete.target.requires/sparky-stereo-boot-login.service"
for t in multi-user hibernate hybrid-sleep suspend-then-hibernate; do
	mkdir -p "$D/usr/lib/systemd/system/$t.target.wants"
	ln -s ../sparky-stereo-boot-finished.service "$D/usr/lib/systemd/system/$t.target.wants/sparky-stereo-boot-finished.service"
done
# this computer's DKMS key (0.1.8, ORDER 374): beside shim and checked against the MOK list at every boot, and placed
# when DKMS makes it (the first boot's signing)
ln -s ../sparky-stereo-boot-secureboot.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-boot-secureboot.service"
for u in sparky-stereo-boot-export.path sparky-stereo-boot-export.service; do
	install -D -m 644 "$HERE/systemd/user/$u" "$D/usr/lib/systemd/user/$u"
	ln -s ../$u "$D/usr/lib/systemd/user/default.target.wants/$u"
done
# the boot's messages, word for word, as journal catalogs: the edition's one engine keeps the boot's problems and its
# session notifier shows them (0.1.6, ORDER 350)
# (the engine runs in a container: it is a package program)
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}catalog-$PKG" --ulimit core=1 --cpus "${CPUS:-4}" --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -v "$HERE/lang":/lang:ro -v "$D":"$D" "${SPARKY_BUILD_IMAGE:-plymouth-481-base:1}" \
	sparky-stereo-problems catalog sparky-stereo-boot /lang "$D/usr/lib/systemd/catalog" --subject LOCAL19
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
# the menu is never drawn without a loaded font (0.1.10, ORDER 572): right after Debian's 00_header
install -D -m 755 "$HERE/grub/01_sparky_stereo_menu" "$D/etc/grub.d/01_sparky_stereo_menu"
# after a start that did not finish (0.1.11, ORDER 572b): each Linux entry records its start through the load_video
# call Debian's 10_linux writes into it (01_sparky_stereo_menu, 0.1.13), so grub2-common's 10_linux is no longer
# diverted (rows 629/802: Debian Policy, appendix 7, "Do not attempt to divert a conffile"); the menu's last entry
# says why the menu is shown
install -D -m 755 "$HERE/lib/login-check" "$D/usr/lib/sparky-stereo-boot/login-check"
install -D -m 755 "$HERE/grub/90_sparky_stereo_start" "$D/etc/grub.d/90_sparky_stereo_start"
install -D -m 755 "$HERE/kernel/zz-sparky-stereo-secureboot" "$D/etc/kernel/postinst.d/zz-sparky-stereo-secureboot"
# two kernels per flavour (0.1.4): the kernel hook records an install, the service waits for apt and dpkg and purges
install -D -m 755 "$HERE/lib/kernel-keep.py" "$D/usr/lib/sparky-stereo-boot/kernel-keep.py"
install -D -m 755 "$HERE/kernel/zz-sparky-stereo-kernel-keep" "$D/etc/kernel/postinst.d/zz-sparky-stereo-kernel-keep"
for u in sparky-stereo-kernel-keep.path sparky-stereo-kernel-keep.service; do
	install -D -m 644 "$HERE/systemd/system/$u" "$D/usr/lib/systemd/system/$u"
done
mkdir -p "$D/usr/lib/systemd/system/paths.target.wants"
ln -s ../sparky-stereo-kernel-keep.path "$D/usr/lib/systemd/system/paths.target.wants/sparky-stereo-kernel-keep.path"
ln -s ../sparky-stereo-boot-dkms-key.path "$D/usr/lib/systemd/system/paths.target.wants/sparky-stereo-boot-dkms-key.path"
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
	/etc/grub.d/35_sparky_stereo_secureboot /etc/grub.d/01_sparky_stereo_menu /etc/grub.d/90_sparky_stereo_start /etc/kernel/postinst.d/zz-sparky-stereo-secureboot \
	/etc/kernel/postinst.d/zz-sparky-stereo-kernel-keep /etc/initramfs-tools/update-initramfs.conf.sparky-stereo > "$D/DEBIAN/conffiles"
cat > "$D/DEBIAN/preinst" <<'SCRIPT'
#!/bin/sh
# initramfs-tools' update-initramfs.conf moves aside for the edition's (update_initramfs=all)
set -e
if [ "$1" = install ] || [ "$1" = upgrade ]; then
	f=/etc/initramfs-tools/update-initramfs.conf
	before=$(dpkg-divert --listpackage "$f")
	dpkg-divert --package sparky-stereo-boot --add --rename --divert "$f.debian" "$f" >/dev/null
	# initramfs-tools unpacked earlier in this dpkg run keeps its conffile as $f.dpkg-new until it is configured; our
	# link at $f is unpacked through that same name and would replace it, so initramfs-tools' conffile would never be
	# installed (rows 629/802: dpkg recorded it "newconffile"). It goes where dpkg now installs initramfs-tools' copy.
	if [ -z "$before" ] && [ -e "$f.dpkg-new" ] && [ ! -e "$f.debian.dpkg-new" ]; then
		mv "$f.dpkg-new" "$f.debian.dpkg-new"
	fi
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
		for u in sparky-stereo-boot.socket:LOCAL22 sparky-stereo-kernel-keep.path:LOCAL59 sparky-stereo-boot-dkms-key.path:LOCAL67; do
			if [ "$(systemctl is-enabled "${u%:*}" 2>/dev/null || :)" = masked ]; then
				python3 $P say LOCAL55 "${u%:*}" "${u%:*}"   # the system's own choice
			else
				python3 $P run "start-${u%:*}" "${u#*:}" -- systemctl start "${u%:*}" || :
			fi
		done
	fi
	# the Sparky Stereo OS certificate, and this computer's DKMS certificate (0.1.8), next to every shim on the EFI
	# system partition: a failure is said and kept by secureboot.py, and the package configures (this system boots
	# without them until Secure Boot needs the keys)
	python3 /usr/lib/sparky-stereo-boot/secureboot.py esp || :
	# the kernel line takes ${sparky_stereo_boot} from GRUB's environment block (0.1.0), the menu the Secure Boot
	# enrolment entry (0.1.3), 30-sparky-stereo-boot.cfg says what GRUB is given and keeps it (0.1.5), the menu's
	# text has one size for every screen (0.1.7), the menu has the entry for this computer's DKMS key (0.1.8), and it is
	# hidden when this is the only system, with a font the signed GRUB loads under Secure Boot (0.1.10); a
	# failed update-grub fails the package, as grub2's postinst does
	# 0.1.10 (ORDER 572): the menu is hidden when this is the only system and shown when another one is found. The
	# installer looks for another system and turns os-prober on (sparky-stereo-dual-boot.cfg); a system installed
	# before that rule was never looked at for another Linux, so an upgrade looks once, on the running system only
	# (not while an image is built), and writes the same file when it finds one. A failed os-prober is said; the
	# menu then follows what the files say
	if [ -n "$2" ] && dpkg --compare-versions "$2" lt 0.1.10 && [ -d /run/systemd/system ] && \
		[ ! -e /etc/default/grub.d/sparky-stereo-dual-boot.cfg ] && [ ! -e /var/lib/sparky-stereo-boot/menu-probed ] && \
		command -v os-prober >/dev/null 2>&1 && ! grep -qs '^GRUB_DISABLE_OS_PROBER=' /etc/default/grub; then
		mkdir -p /var/lib/sparky-stereo-boot
		if others=$(os-prober 2>/dev/null); then
			name=$(printf '%s\n' "$others" | awk -F: 'NF >= 2 && $2 != "" { print $2; exit }')
			if [ -n "$name" ]; then
				mkdir -p /etc/default/grub.d
				printf '%s\n' '# Sparky Stereo OS: written by sparky-stereo-boot at an upgrade because another system was found beside this one.' \
					'# os-prober adds it to the boot menu at every update-grub.' 'GRUB_DISABLE_OS_PROBER=false' \
					> /etc/default/grub.d/sparky-stereo-dual-boot.cfg
				python3 $P say LOCAL81 "$name"
			fi
			: > /var/lib/sparky-stereo-boot/menu-probed
		else
			echo "sparky-stereo-boot: os-prober failed (exit $?); whether another system is on this computer was not checked" >&2
		fi
	fi
	# 0.1.13 (rows 629/802): grub2-common's 10_linux, diverted by 0.1.11 and 0.1.12, goes back to its name with whatever
	# the person changed in it. Here and not in the preinst: a preinst removal would make dpkg delete grub2-common's file
	# as the link our older version shipped at that name (measured). dpkg removed that link at this unpack, so until
	# here the name was empty; the update-grub below writes the menu again from grub2-common's own file.
	if [ "$(dpkg-divert --listpackage /etc/grub.d/10_linux)" = sparky-stereo-boot ]; then
		if [ "$(readlink /etc/grub.d/10_linux)" = /usr/lib/sparky-stereo-boot/10_linux ]; then
			rm -f /etc/grub.d/10_linux
		fi
		dpkg-divert --package sparky-stereo-boot --remove --rename \
			--divert /etc/sparky-stereo-boot/10_linux.debian /etc/grub.d/10_linux >/dev/null
		rmdir /etc/sparky-stereo-boot 2>/dev/null || :
	fi
	# 0.1.11 (ORDER 572b): the Linux entries record each start and the menu shows by itself after one that did not
	# finish; 0.1.13 records it through load_video and 0.1.14 names a person's GRUB_GFXPAYLOAD_LINUX=text (LOCAL102), so
	# the menu and that problem are written again, as the last step; 0.1.15 (ORDER 666) writes the Secure Boot enrolment
	# entries only where the firmware has Secure Boot, so the menu is written again at that upgrade too
	if { [ -z "$2" ] || dpkg --compare-versions "$2" lt 0.1.15; } && [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then
		python3 $P run update-grub LOCAL21 -- update-grub || failed=1
	fi
	[ -z "$failed" ] || exit 1
fi
if [ "$1" = triggered ]; then
	# shim's or GRUB's signed programs were installed again: the certificates beside them again (said and kept by
	# secureboot.py when they cannot be placed)
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
*) lang=${lang%%_*}; case $lang in pl|fr|de|es|ja|ko) ;; *) lang=en ;; esac ;;
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
		# initramfs-tools unpacked in this same dpkg run waits to be configured with its conffile at the diverted name:
		# it goes back to the name dpkg will now look for (the preinst's move, undone; rows 629/802)
		f=/etc/initramfs-tools/update-initramfs.conf
		if [ -e "$f.debian.dpkg-new" ] && [ ! -e "$f.dpkg-new" ]; then
			mv "$f.debian.dpkg-new" "$f.dpkg-new"
		fi
	fi
	# Debian's /etc/grub.d/10_linux comes back, when 0.1.11 or 0.1.12 diverted it and 0.1.13's postinst never ran; only
	# at a removal: 0.1.13 adds no diversion, and on abort-upgrade the older version keeps its own
	if [ "$1" = remove ] && [ "$(dpkg-divert --listpackage /etc/grub.d/10_linux)" = sparky-stereo-boot ]; then
		if [ "$(readlink /etc/grub.d/10_linux)" = /usr/lib/sparky-stereo-boot/10_linux ]; then
			rm -f /etc/grub.d/10_linux
		fi
		dpkg-divert --package sparky-stereo-boot --remove --rename \
			--divert /etc/sparky-stereo-boot/10_linux.debian /etc/grub.d/10_linux >/dev/null
		rmdir /etc/sparky-stereo-boot 2>/dev/null || :
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
	for f in /boot/efi/EFI/*/sparky-stereo-secureboot-2026.der /boot/efi/EFI/*/dkms-this-computer.der /boot/efi/EFI/sparky-stereo-boot/grubenv; do
		[ -e "$f" ] || continue
		rm -f "$f" || say 58 "$f"
	done
	rmdir /boot/efi/EFI/sparky-stereo-boot 2>/dev/null || :
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
Depends: grub-common, os-prober, libdrm2, libstereo-policy1 (>= 1.15.0), python3, systemd, sparky-stereo-problems (>= 0.1.0)
Recommends: plymouth (>= 26.134.222-1+stereo3d4), sparky-stereo-plymouth (>= 20261117~sparky9~0)
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
  too. GRUB's menu is hidden when this is the only system; after a start
  that did not finish it shows by itself at the next start, with the
  older kernel in it, the file systems are checked at that start, and
  the person is told at login what the check found.
  .
  Under Secure Boot, the edition's key and this computer's DKMS key are
  kept next to shim on the EFI system partition, with a GRUB entry that
  enrolls each one; a DKMS key that is not enrolled while modules signed
  with it are installed is said.
  .
  Nothing in the boot's upkeep fails silently: a failed update-grub,
  boot image, Secure Boot certificate, kernel cleanup or 3D splash
  hand-over says what failed, why and what to do, in the system's
  language, and is kept with its output until it is repaired;
  sparky-stereo-boot status lists it and the session shows it.
CONTROL
(cd "$D" && find usr etc -type f -exec md5sum {} + | grep -v ' etc/' | sort -k2) > "$D/DEBIAN/md5sums"
chmod 644 "$D/DEBIAN/control" "$D/DEBIAN/md5sums" "$D/DEBIAN/conffiles"
# the gate runs in a container that is given the host's facts; the source package is built again with dpkg-buildpackage
# (repo/rebuild-script-source.py: payload and controls equal, the genuine .buildinfo and .changes kept, as
# sparky-stereo-look does), so check-debs writes the complete build record (ORDER 639)
IMAGE=${SPARKY_BUILD_IMAGE:-plymouth-481-base:1}
TREE=$(cd "$HERE/../../.." && pwd)
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lean-standalone-sparky-stereo-boot" --ulimit core=1 --cpus "${CPUS:-4}" --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -e PYTHONPATH="$TREE/sparky-os" \
	-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
	-v "$TREE":"$TREE":ro -v "$D":"$D" -v "$OUT":"$OUT" "$IMAGE" sh -c 'python3 -m lean.standalone "$1" "$2" --authoring "$3" && python3 "$PYTHONPATH/repo/rebuild-script-source.py" "$2/$4_$5.dsc" && cd "$2" && python3 -m lean.release check-debs ./*_all.deb' sh "$D" "$OUT" "$HERE" "$PKG" "$VERSION"

