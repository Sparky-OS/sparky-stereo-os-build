#!/bin/sh
# Packs the beta from the root file system with Sparky Backup Core Stereo, the way SparkyLinux packs its
# images (sparkybackup dist on the system itself), run in a chroot: the staged packages go in, the build's
# own apt sources, policy and DKMS signing key come out, and sparkybackup-stereo makes the ISO.
# Runs as root inside beta-iso-lutz-build:1 (privileged). Mounts as rootfs.sh, plus /work (the packer's
# work tree) and /out (the ISO and its files), both outside the root file system.
# Environment: LABEL (menu label), ISONAME (file name), SIGNED_MODULES (optional: a folder whose
# lib/modules/... files replace the DKMS modules, signed with the edition's key by the main session),
# SIGNED_KERNEL (optional: the linux-image package signed with the edition's key, installed over the tree's),
# LEAN (1: the packer runs dpkg-stereo's pre-squashfs hook, the Lean Code projection, on the folders it squashes;
# 1 is mandatory for release builds; 0 requires ISO_PURPOSE=benchmark and a -nolean- name).
# The iso step packs from an overlay of the root file system (upper layer in /work), so the root file system is
# the same for every pack: two packs with LEAN=0 and LEAN=1 differ only in the hook.
# Usage: pack.sh configure|iso|all
set -eu
R=/rootfs
STEP=${1:-all}
LABEL=${LABEL:-Sparky Stereo OS 9 Mashtabba beta 2}
ISONAME=${ISONAME:-sparky-stereo-os-9-mashtabba-beta2-x86_64.iso}
LEAN=${LEAN:-1}
case "$LEAN" in
1) ;;
0)
	[ "${ISO_PURPOSE:-release}" = benchmark ] || { echo "!! release images require LEAN=1"; exit 1; }
	case "$ISONAME" in *-nolean-*.iso) ;; *) echo "!! benchmark control needs a -nolean- ISO name"; exit 1 ;; esac ;;
*) echo "!! LEAN must be 0 or 1"; exit 1 ;;
esac
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
# dpkg-stereo's hooks stay quiet for every dpkg run of the build (the signed kernel's included): the image is
# projected once, in the iso step, when LEAN=1
export DPKG_STEREO_DISABLE=1 DPKG_STEREO_NO_PROJECT=1
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
	echo "== $(date -u +%T) staged packages: the packer fork, hardware, service defaults, installer settings and branding, calamares, info, look, artwork, splash, boot, GRUB translations, headers 8.1"
	# the build's sources and stubs (rootfs.sh) again, so the step can be repeated
	printf 'Types: deb\nURIs: file:/stage\nSuites: ./\nTrusted: yes\n' > $R/etc/apt/sources.list.d/beta-build-stage.sources
	printf 'Types: deb\nURIs: file:/repo\nSuites: ./\nTrusted: yes\n' > $R/etc/apt/sources.list.d/sparky-stereo-build.sources
	printf '#!/bin/sh\nexit 101\n' > $R/usr/sbin/policy-rc.d; chmod 755 $R/usr/sbin/policy-rc.d
	for f in /usr/bin/os-prober /usr/sbin/grub-mkconfig; do
		inr dpkg-divert --list "$f" | grep -q . || inr dpkg-divert --local --rename --add "$f"
		printf '#!/bin/sh\nexit 0\n' > "$R$f"; chmod 755 "$R$f"
	done
	inr apt-get update
	echo "== $(date -u +%T) the edition's repository (Daniel, 2026-10-16): sparky-stereo-apt with its keyring, deb-multimedia's keyring package"
	# first, so its pin (o=Sparky Stereo OS at 1001) ranks the staged packages above SparkyLinux's for what follows.
	# The recipe's own copies of the files it ships go before its first install, so the package owns them; on a
	# second pack the package is there already, and its files are put back if anything removed them.
	apt_in install deb-multimedia-keyring
	if ! inr dpkg-query -W -f '${Status}' sparky-stereo-apt 2>/dev/null | grep -q 'ok installed'; then
		rm -f $R/etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources $R/etc/apt/keyrings/deb-multimedia-keyring.pgp \
			$R/etc/apt/preferences.d/sparky-stereo $R/etc/apt/preferences.d/sparky-stereo-only-ours
	fi
	apt_in install sparky-stereo-keyring
	apt_in -o Dpkg::Options::=--force-confmiss install --reinstall sparky-stereo-apt
	for f in sources.list.d/sparky-stereo.sources sources.list.d/sparky-stereo-deb-multimedia.sources preferences.d/sparky-stereo preferences.d/sparky-stereo-only-ours; do
		[ -s $R/etc/apt/$f ] || { echo "!! /etc/apt/$f is missing"; exit 1; }
	done
	inr apt-get update
	echo "== $(date -u +%T) the development repository's current versions of every installed package it carries"
	# only packages already in the image, and only upgrades: the edition's pin makes the repository's builds the candidates
	inr sh -c "awk '/^Package: /{print \$2}' /repo/Packages | sort -u | xargs dpkg-query -W -f '\${Package} \${Status}\n' 2>/dev/null | awk '/ ok installed\$/{print \$1}'" > /tmp/beta-repo-installed.list
	apt_in install --only-upgrade $(cat /tmp/beta-repo-installed.list)
	rm -f /tmp/beta-repo-installed.list
	apt_in install --reinstall sparky-backup-core-stereo sparky-stereo-hardware sparky-stereo-service-defaults calamares-settings-sparky-stereo \
		calamares sparky-stereo-calamares-branding sparky-stereo-info sparky-stereo-look sparkyos-artwork sparkyos-plymouth sparky-stereo-boot \
		linux-headers-7.3.0-rc6-stereo3d8
	echo "== $(date -u +%T) the boot chain in 3D (ORDER 138): the stereo Plymouth, sparky-stereo-boot, the stereo splash themes; GRUB's menu translated; Kubabbar Glass for Quick Settings"
	apt_in install plymouth libplymouth5 plymouth-themes plymouth-label sparky-stereo-boot sparky-stereo-plymouth sparky-stereo-grub-l10n \
		sparky-stereo-look-kubabbar-glass sparky-stereo-look-kubabbar-glass-menubar
	# Create Stereo in the file menus, which the installer's slides show (stereo-create, in no list yet)
	apt_in install stereo-create
	# Lean Code (ORDER 14): dpkg-stereo in both packs of a pair, so they differ only by the projection
	apt_in install dpkg-stereo
	echo "== $(date -u +%T) Plasma Login Manager as the display manager (Daniel's preference); SDDM stays installed, not started"
	echo "plasma-login-manager shared/default-x-display-manager select plasma-login-manager" | inr debconf-set-selections
	echo "sddm shared/default-x-display-manager select plasma-login-manager" | inr debconf-set-selections
	apt_in install plasma-login-manager
	echo /usr/bin/plasmalogin > $R/etc/X11/default-display-manager
	ln -sf /usr/lib/systemd/system/plasmalogin.service $R/etc/systemd/system/display-manager.service
	ls -l $R/etc/systemd/system/display-manager.service; cat $R/etc/X11/default-display-manager
	echo "== $(date -u +%T) the edition's removals (lists/base-remove.list) that the image still has"
	rm_list=$(grep -v '^#' /edition-lists/base-remove.list | while read -r p; do
		if [ -n "$p" ] && inr dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q 'ok installed'; then echo "$p"; fi; done)
	[ -z "$rm_list" ] || apt_in remove $rm_list
	# usbguard blocks USB keyboards and pointers present at boot (the boot lane's dev VM); it never goes in
	if inr dpkg-query -W -f '${Status}' usbguard 2>/dev/null | grep -q 'ok installed'; then apt_in purge usbguard; fi
	echo "== $(date -u +%T) the default boot splash: $(inr plymouth-set-default-theme)"
	# the packages SparkyLinux's securebootinstall asks apt for that the image lacks (an offline install finds the rest)
	for p in libjcat1 grub-efi-amd64-signed-template shim-helpers-amd64-signed-template; do
		apt_in install --no-install-recommends "$p" || echo "!! $p: not installed"
	done
	echo "== $(date -u +%T) GRUB's EFI packages for an offline UEFI install (calamares-settings-sparky-stereo's offline step)"
	O=/usr/share/sparky-stereo/offline-debs
	rm -rf $R$O; mkdir -p $R$O
	GV=$(inr dpkg-query -W -f '${Version}' grub-efi-amd64-bin)
	inr sh -c "cd $O && apt-get download grub-efi=$GV grub-efi-amd64=$GV"
	for p in libjcat1 grub-efi-amd64-signed-template shim-helpers-amd64-signed-template; do
		inr dpkg-query -W -f '${Status}' "$p" 2>/dev/null | grep -q installed || inr sh -c "cd $O && apt-get download $p" || true
	done
	(cd $R$O && dpkg-scanpackages -m . 2>/dev/null > Packages && ls)
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
	rmdir $R/stage $R/repo 2>/dev/null || true
	umounts
	# the packer's work folder from the last pack goes first: it would otherwise carry that pack's files (its package
	# list) into this image
	rm -rf /work/sparkybackup-sys
	# an overlay of the root file system: what the packer and the hook change stays in the upper layer, so every
	# pack starts from the same root file system
	O=/lean-merged U=/overlay
	rm -rf $U/upper $U/work; mkdir -p $U/upper $U/work $O
	mount -t overlay overlay -o lowerdir=$R,upperdir=$U/upper,workdir=$U/work $O
	R=$O
	trap 'umounts; umount $O 2>/dev/null || true' EXIT
	mounts
	for m in var/cache/apt/archives stage repo; do mountpoint -q $R/$m && umount $R/$m || true; done
	rmdir $R/stage $R/repo 2>/dev/null || true
	hook=
	if [ "$LEAN" = 1 ]; then
		hook=/usr/lib/dpkg-stereo/presquashfs-hook
		[ -x $R$hook ] || { echo "!! LEAN=1 needs dpkg-stereo's $hook in the image"; exit 1; }
	fi
	# the image's name and label for this pack (a pair of packs from one configured tree differs in name)
	sed -i -e "s|^ISOLABELFULL=.*|ISOLABELFULL=\"$LABEL\"|" -e "s|^CUSTOMISO=.*|CUSTOMISO=\"$ISONAME\"|" $R/etc/sparkybackup/sparkybackup-stereo.conf
	echo "== $(date -u +%T) LEAN=$LEAN hook=${hook:-none}; top folders of the image: $(ls $R | tr '\n' ' ')"
	echo "== $(date -u +%T) sparkybackup-stereo dist"
	t0=$(date +%s)
	inr env PRESQUASHFS_HOOK="$hook" LEANCODE_JOBS=4 sparkybackup-stereo dist
	echo "== $(date -u +%T) packed in $(( $(date +%s) - t0 )) s (LEAN=$LEAN)"
	# the projection's build record beside the ISO
	for f in lean-code-projection.tsv lean-code-left.tsv; do
		[ -f /work/sparkybackup-sys/$f ] && xz -T1 -c /work/sparkybackup-sys/$f > /out/$ISONAME.${f%.tsv}.tsv.xz
	done
	if [ "$LEAN" = 1 ]; then
		# Bind the successful pre-squashfs pass to the final ISO, not just its name.
		cp /work/sparkybackup-sys/lc-image.json /out/$ISONAME.lc-image.json
		PYTHONPATH="$R/usr/lib/dpkg-stereo" python3 -m lean.release seal-iso \
			"/out/$ISONAME" "/out/$ISONAME.lean-code-projection.tsv.xz" "/out/$ISONAME.lc-image.json"
	fi
	ls -la /out
fi
