#!/bin/sh
# Builds the beta's root file system: Sparky KDE 2026.09's package set on today's Debian testing,
# the edition (sparky-stereo with its desktop, system, hardware-support and look metas and their
# Recommends), our stereo kernel with Debian's signed kernel beside it, NVIDIA's 615 userspace with the
# edition's open modules, the installer and the live system. Runs as root inside beta-iso-lutz-build:1
# (privileged, for the chroot's mounts).
# Mounts: /rootfs (the tree, on /mnt/build), /cache (apt's archives, outside the tree), /repo (the edition's
# development repository, read-only), /stage (the lane's staged packages, a flat repository), /build,
# /edition-apt, /edition-lists (read-only).
# Usage: rootfs.sh base|packages|all
set -eu
R=/rootfs
STEP=${1:-all}
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

mounts() {
	mountpoint -q $R/proc || mount -t proc proc $R/proc
	mountpoint -q $R/sys || mount -t sysfs sys $R/sys
	mountpoint -q $R/dev || { mount --rbind /dev $R/dev; mount --make-rslave $R/dev; }
	mkdir -p $R/repo $R/stage $R/var/cache/apt/archives
	mountpoint -q $R/repo || mount --bind /repo $R/repo
	mountpoint -q $R/stage || mount --bind /stage $R/stage
	mountpoint -q $R/var/cache/apt/archives || mount --bind /cache $R/var/cache/apt/archives
}
umounts() {
	for m in var/cache/apt/archives stage repo dev sys proc; do
		mountpoint -q $R/$m && umount -R $R/$m || true
	done
}
trap umounts EXIT
inr() { chroot $R "$@"; }
apt_in() { chroot $R apt-get -y -o Dpkg::Use-Pty=0 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"; }

if [ "$STEP" = base ] || [ "$STEP" = all ]; then
	echo "== $(date -u +%T) base: minbase from Debian testing"
	mmdebstrap --mode=root --variant=minbase --components=main,contrib,non-free,non-free-firmware --architectures=amd64 \
		--include=ca-certificates,curl,gnupg,apt-utils,dpkg-dev testing $R http://deb.debian.org/debian
	mounts
	# the build's own apt sources (removed before packing), keys and the edition's pins
	cp /build/apt-setup.sh $R/tmp/
	mkdir -p $R/edition-apt && cp /edition-apt/sparky-stereo /edition-apt/sparky-stereo-only-ours $R/edition-apt/
	inr sh /tmp/apt-setup.sh /
	rm -rf $R/edition-apt $R/tmp/apt-setup.sh $R/etc/apt/sources.list.d/debian.sources
	mv $R/etc/apt/sources.list.d/sparky.sources $R/etc/apt/sources.list.d/beta-build-sparky.sources
	cat > $R/etc/apt/sources.list.d/beta-build-stage.sources <<'EOF'
Types: deb
URIs: file:/stage
Suites: ./
Trusted: yes
EOF
	# no services start in the chroot; DKMS on 4 threads
	printf '#!/bin/sh\nexit 101\n' > $R/usr/sbin/policy-rc.d; chmod 755 $R/usr/sbin/policy-rc.d
	mkdir -p $R/etc/dkms/framework.conf.d
	echo 'parallel_jobs=4' > $R/etc/dkms/framework.conf.d/beta-build.conf
	inr apt-get update
fi

if [ "$STEP" = packages ] || [ "$STEP" = all ]; then
	mounts
	# packages such as sparky-grub-theme and sparky-info run grub-mkconfig when they are configured, as on
	# an installed system. In a chroot it would probe the build machine's disks, and os-prober would mount
	# them, so both are stubs while the tree is built; pack.sh puts the real programs back.
	mkdir -p $R/boot/grub
	for f in /usr/bin/os-prober /usr/sbin/grub-mkconfig; do
		inr dpkg-divert --list "$f" | grep -q . || inr dpkg-divert --local --rename --add "$f"
		printf '#!/bin/sh\nexit 0\n' > "$R$f"; chmod 755 "$R$f"
	done
	# OpenZFS 2.4.4 supports Linux up to 7.2 (its META) and its configure stops on 7.3 ("iops->create()
	# passes flags"); with zfs-dkms installed DKMS's hook fails and so does every kernel's postinst.
	# SparkyLinux's image has no ZFS; here it came with Calamares' Recommends. Kept out while building.
	printf 'Package: zfs-dkms zfsutils-linux zfs-zed\nPin: release *\nPin-Priority: -1\n' > $R/etc/apt/preferences.d/beta-build-no-zfs
	inr dpkg --purge zfs-zed zfsutils-linux zfs-dkms 2>/dev/null || true
	inr apt-get update
	inr dpkg --configure -a
	echo "== $(date -u +%T) Sparky KDE 2026.09's package set"
	cp /build/base-list.sh /build/sparky-kde-2026.09.names /edition-lists/base-remove.list $R/tmp/
	inr env NAMES=/tmp/sparky-kde-2026.09.names REMOVE=/tmp/base-remove.list sh /tmp/base-list.sh > /tmp/base
	[ -s /tmp/base ] || { echo "rootfs: empty base list" >&2; exit 1; }
	echo "   $(wc -l < /tmp/base) names"
	# the answers SparkyLinux's own image carries: US keyboard, the firmware licences accepted
	printf '%s\n' "keyboard-configuration keyboard-configuration/layoutcode string us" \
		"firmware-ipw2x00 firmware-ipw2x00/license/accepted boolean true" \
		"firmware-ivtv firmware-ivtv/license/accepted boolean true" | inr debconf-set-selections
	apt_in install $(cat /tmp/base)
	echo "== $(date -u +%T) the edition: metas with their Recommends"
	apt_in install sparky-stereo-desktop sparky-stereo-system sparky-stereo-hardware-support sparky-stereo-look \
		sparky-stereo-calamares-branding
	echo "== $(date -u +%T) the edition's top meta and languages (German and English packs; the rest stay Recommends)"
	apt_in install --no-install-recommends sparky-stereo sparky-stereo-languages
	apt_in install hunspell-de-de hyphen-de mythes-de libreoffice-l10n-de libreoffice-help-de hunspell-en-gb hunspell-en-us hyphen-en-us mythes-en-us libreoffice-help-en-us locales-all
	echo "== $(date -u +%T) kernels: Debian's signed kernel beside ours; NVIDIA 615 with the edition's open modules"
	apt_in install linux-image-amd64 nvidia-driver=615.71.09-2 nvidia-kernel-open-dkms-stereo3d
	apt_in clean
fi
echo "== $(date -u +%T) installed: $(inr dpkg-query -f '${binary:Package}\n' -W | wc -l) packages, $(du -sxh $R | cut -f1)"
inr dkms status || true
