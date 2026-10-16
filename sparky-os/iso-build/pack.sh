#!/bin/sh
# Packs the beta from the root file system with Sparky Backup Core Stereo, the way SparkyLinux packs its
# images (sparkybackup dist on the system itself), run in a chroot: the staged packages go in, the build's
# own apt sources, policy and DKMS signing key come out, and sparkybackup-stereo makes the ISO.
# Runs as root inside beta-iso-lutz-build:1 (privileged). Mounts as rootfs.sh, plus /work (the packer's
# work tree) and /out (the ISO and its files), both outside the root file system.
# Environment: LABEL (menu label), ISONAME (file name), SIGNED_MODULES (optional: a folder whose
# lib/modules/... files replace the DKMS modules, signed with the edition's key by the main session),
# SIGNED_KERNEL (optional: the linux-image package signed with the edition's key, installed over the tree's).
# Usage: pack.sh configure|iso|all
set -eu
R=/rootfs
STEP=${1:-all}
LABEL=${LABEL:-Sparky Stereo OS 9 Mashtabba beta 1}
ISONAME=${ISONAME:-sparky-stereo-os-9-mashtabba-beta1-x86_64.iso}
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
inr() { chroot $R "$@"; }
apt_in() { chroot $R apt-get -y -o Dpkg::Use-Pty=0 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"; }
mounts() {
	mountpoint -q $R/proc || mount -t proc proc $R/proc
	mountpoint -q $R/sys || mount -t sysfs sys $R/sys
	mountpoint -q $R/dev || { mount --rbind /dev $R/dev; mount --make-rslave $R/dev; }
	mkdir -p $R/repo $R/stage $R/var/cache/apt/archives $R/home/sparkybackup-sys $R/home/sparkybackup-out
	mountpoint -q $R/repo || mount --bind /repo $R/repo
	mountpoint -q $R/stage || mount --bind /stage $R/stage
	mountpoint -q $R/var/cache/apt/archives || mount --bind /cache $R/var/cache/apt/archives
	mountpoint -q $R/home/sparkybackup-sys || mount --bind /work $R/home/sparkybackup-sys
	mountpoint -q $R/home/sparkybackup-out || mount --bind /out $R/home/sparkybackup-out
}
umounts() {
	for m in home/sparkybackup-out home/sparkybackup-sys var/cache/apt/archives stage repo dev sys proc; do
		mountpoint -q $R/$m && umount -R $R/$m || true
	done
}
trap umounts EXIT
mounts

if [ "$STEP" = configure ] || [ "$STEP" = all ]; then
	echo "== $(date -u +%T) staged packages: the packer fork, hardware 0.1.8, service defaults, installer settings, calamares, headers 8.1"
	# the build's sources and stubs (rootfs.sh) again, so the step can be repeated
	printf 'Types: deb\nURIs: file:/stage\nSuites: ./\nTrusted: yes\n' > $R/etc/apt/sources.list.d/beta-build-stage.sources
	printf 'Types: deb\nURIs: file:/repo\nSuites: ./\nTrusted: yes\n' > $R/etc/apt/sources.list.d/sparky-stereo-build.sources
	printf '#!/bin/sh\nexit 101\n' > $R/usr/sbin/policy-rc.d; chmod 755 $R/usr/sbin/policy-rc.d
	for f in /usr/bin/os-prober /usr/sbin/grub-mkconfig; do
		inr dpkg-divert --list "$f" | grep -q . || inr dpkg-divert --local --rename --add "$f"
		printf '#!/bin/sh\nexit 0\n' > "$R$f"; chmod 755 "$R$f"
	done
	inr apt-get update
	apt_in install --reinstall sparky-backup-core-stereo sparky-stereo-hardware sparky-stereo-service-defaults calamares-settings-sparky-stereo \
		calamares linux-headers-7.3.0-rc6-stereo3d8
	apt_in clean
	echo "== $(date -u +%T) the image's apt sources: the build's own sources go; Debian, SparkyLinux (sparky-apt), deb-multimedia and NVIDIA's CUDA repository stay"
	rm -f $R/etc/apt/sources.list.d/beta-build-*.sources $R/etc/apt/sources.list.d/sparky-stereo-build.sources $R/etc/apt/preferences.d/beta-build-*
	rm -f $R/usr/sbin/policy-rc.d $R/etc/dkms/framework.conf.d/beta-build.conf
	# the real os-prober and grub-mkconfig, stubs while the tree was built (rootfs.sh)
	for f in /usr/bin/os-prober /usr/sbin/grub-mkconfig; do
		if inr dpkg-divert --list "$f" | grep -q local; then rm -f "$R$f"; inr dpkg-divert --local --rename --remove "$f"; fi
	done
	rm -f $R/boot/grub/grub.cfg
	if [ -n "${SIGNED_KERNEL:-}" ] && [ -f "$SIGNED_KERNEL" ]; then
		echo "== $(date -u +%T) the stereo kernel signed with the edition's key: $(basename "$SIGNED_KERNEL")"
		cp "$SIGNED_KERNEL" $R/tmp/signed-kernel.deb
		inr dpkg -i /tmp/signed-kernel.deb
		rm -f $R/tmp/signed-kernel.deb
	fi
	if [ -n "${SIGNED_MODULES:-}" ] && [ -d "$SIGNED_MODULES/lib/modules" ]; then
		echo "== $(date -u +%T) DKMS modules signed with the edition's key"
		cp -a "$SIGNED_MODULES/lib/modules/." $R/lib/modules/
		inr depmod -a 7.3.0-rc6-stereo3d8
	fi
	# DKMS made its own signing key while building in the chroot; a private key never ships
	rm -f $R/var/lib/dkms/mok.key $R/var/lib/dkms/mok.pub
	# each installed system gets its own identity
	: > $R/etc/machine-id; rm -f $R/var/lib/dbus/machine-id
	rm -f $R/etc/nvme/hostid $R/etc/nvme/hostnqn
	rm -f $R/etc/ssh/ssh_host_*
	echo "== $(date -u +%T) the Stereo profile's values"
	DK=$(ls $R/boot/vmlinuz-*-amd64 | sed 's|.*/vmlinuz-||' | sort -V | tail -n1)
	C=$R/etc/sparkybackup/sparkybackup-stereo.conf
	sed -i -e "s|^ISOLABELFULL=.*|ISOLABELFULL=\"$LABEL\"|" -e "s|^CUSTOMISO=.*|CUSTOMISO=\"$ISONAME\"|" \
		-e "s|^LIVEKERNEL=.*|LIVEKERNEL=\"7.3.0-rc6-stereo3d8\"|" -e "s|^LIVEKERNEL2=.*|LIVEKERNEL2=\"$DK\"|" $C
	grep -q '^OUTDIR=' $C || printf 'OUTDIR="/home/sparkybackup-out"\n' >> $C
	grep -v '^#' $C | grep -v '^$'
fi

if [ "$STEP" = iso ] || [ "$STEP" = all ]; then
	# the packer squashes every top folder of / but a fixed list: the build's own mount points go first
	for m in var/cache/apt/archives stage repo; do mountpoint -q $R/$m && umount $R/$m || true; done
	rmdir $R/stage $R/repo
	echo "== $(date -u +%T) top folders of the image: $(ls $R | tr '\n' ' ')"
	echo "== $(date -u +%T) sparkybackup-stereo dist"
	t0=$(date +%s)
	inr sparkybackup-stereo dist
	echo "== $(date -u +%T) packed in $(( $(date +%s) - t0 )) s"
	ls -la /out
fi
