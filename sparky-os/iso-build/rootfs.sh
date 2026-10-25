#!/bin/sh
# Builds the image's root file system: Sparky KDE 2026.09's package set on today's Debian testing,
# the edition (sparky-stereo with its desktop, system, hardware-support and look metas and their
# Recommends), the edition's kernel and no other (Daniel, 2026-10-24: Debian's kernel has no stereo 3D and
# is not shipped with the distribution; Secure Boot goes through Debian's shim and GRUB to our signed kernel
# once the edition's key is enrolled), NVIDIA's 615 userspace with the edition's open modules, the installer
# and the live system. Runs as root inside the build image (privileged, for the chroot's mounts).
# Mounts: /rootfs (the tree, on an SSD), /cache (apt's archives, outside the tree), /repo (EDITION_REPO=flat: the
# edition's development repository, read-only; live: empty), /stage (staged packages, a flat repository),
# /build, /edition-apt, /edition-lists, /edition-repo (read-only).
# EDITION_REPO: live (default, the published repository) or flat (/repo), as apt-setup.sh.
# Usage: rootfs.sh base|packages|all
set -eu
R=/rootfs
STEP=${1:-all}
EDITION_REPO=${EDITION_REPO:-live}
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 EDITION_REPO

mounts() {
	mountpoint -q $R/proc || mount -t proc proc $R/proc
	mountpoint -q $R/sys || mount -t sysfs sys $R/sys
	mountpoint -q $R/dev || { mount --rbind /dev $R/dev; mount --make-rslave $R/dev; }
	mkdir -p $R/repo $R/stage $R/var/cache/apt/archives
	mountpoint -q $R/repo || mount --bind /repo $R/repo
	mountpoint -q $R/stage || mount --bind /stage $R/stage
	mountpoint -q $R/var/cache/apt/archives || mount --bind /cache $R/var/cache/apt/archives
	# the container's name resolution (docker run --add-host), so the chroot reaches the hosts the build names
	[ -f $R/etc/hosts ] || : > $R/etc/hosts
	mountpoint -q $R/etc/hosts || mount --bind /etc/hosts $R/etc/hosts
}
umounts() {
	for m in etc/hosts var/cache/apt/archives stage repo dev sys proc; do
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
	inr env EDITION_REPO=$EDITION_REPO sh /tmp/apt-setup.sh /
	rm -rf $R/edition-apt $R/tmp/apt-setup.sh $R/etc/apt/sources.list.d/debian.sources
	mv $R/etc/apt/sources.list.d/sparky.sources $R/etc/apt/sources.list.d/beta-build-sparky.sources
	# Debian's kernels never come in while the tree is built, whatever asks for them (the edition's kernels are
	# named linux-image-<release>-stereo3dN, without -amd64; plain linux-base stays, every kernel uses its tools)
	cat > $R/etc/apt/preferences.d/beta-build-no-debian-kernel <<'EOF'
Package: /^linux-(image|headers|binary|modules|signed|base)-.*amd64(-unsigned)?$/
Pin: release o=Debian
Pin-Priority: -1
EOF
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
	echo "== $(date -u +%T) kernels: the edition's kernel and its headers, no other; NVIDIA 615 with the edition's open modules"
	apt_in install linux-image-sparky-stereo linux-headers-sparky-stereo
	# sparky-stereo-nvidia-driver-lock first: its pin keeps NVIDIA's whole driver at the version the edition's open
	# module is built for (NVIDIA's CUDA repository moves ahead: 615.71.10-1 on 2026-10-25, while the module is 615.71.09-2)
	apt_in install sparky-stereo-nvidia-driver-lock
	apt_in install nvidia-driver nvidia-kernel-open-dkms-stereo3d libnvcuvid1 nvidia-vaapi-driver
	cp /build/boot-kernels.py $R/tmp/
	inr python3 /tmp/boot-kernels.py / || { echo "rootfs: a kernel that is not the edition's is in the tree" >&2; exit 1; }
	rm -f $R/tmp/boot-kernels.py
	echo "== $(date -u +%T) command-not-found: its index is filled at build time, so a live session names the package of a missing program before anyone runs apt update"
	# apt-file's Contents targets are on (50apt-file.conf) and command-not-found's own hook (50command-not-found) builds the index
	# after every apt update: Debian's and deb-multimedia's files come that way. The build's own sources are flat repositories with
	# no Contents, so the edition's packages in them are listed here the way the published repository lists them.
	# The published repository has its Contents (EDITION_REPO=live); a flat development repository has none.
	inr apt-get update
	debs=$(find /repo /stage -name '*.deb' ! -name '*-dbgsym_*' 2>/dev/null)
	if [ -n "$debs" ]; then
		mkdir -p /tmp/cnf
		# shellcheck disable=SC2086
		python3 /edition-repo/make-contents.py /tmp/cnf "amd64 all" $debs
		cp /tmp/cnf/Contents-amd64 $R/var/lib/apt/lists/edition-build_main_Contents-amd64
		cp /tmp/cnf/Contents-all $R/var/lib/apt/lists/edition-build_main_Contents-all
	fi
	inr /usr/lib/cnf-update-db
	[ -s $R/var/lib/command-not-found/commands.db ] || { echo "rootfs: command-not-found's index is empty" >&2; exit 1; }
	# a Debian-only, a deb-multimedia-only and an edition-only program must be in it (cnf-check.py picks the deb-multimedia one)
	cp /build/cnf-check.py $R/tmp/
	inr python3 /tmp/cnf-check.py align_image_stack vlc-stereo || { echo "rootfs: command-not-found's index lacks a program of one of the three sources" >&2; exit 1; }
	rm -f $R/tmp/cnf-check.py
	apt_in clean
fi
echo "== $(date -u +%T) installed: $(inr dpkg-query -f '${binary:Package}\n' -W | wc -l) packages, $(du -sxh $R | cut -f1)"
inr dkms status || true
