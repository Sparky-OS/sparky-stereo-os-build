#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
# vm-proof.sh WORK KERNEL_IMAGE_DEB DEBS_DIR LABEL : a Debian forky system with systemd, the given kernel and the packages of
# DEBS_DIR (dmemcg-booster, sparky-stereo-vram-boost) booted headless in QEMU; a unit run at boot prints what the
# decision and the helpers did on the serial console, then powers off. Needs the rig image (QEMU, e2fsprogs) and /dev/kvm.
#   1. the boot decision (sparky-stereo-vram-boost.service, /run/sparky-stereo-vram-boost/state) and whether
#      dmemcg-booster-system.service was skipped by its condition
#   2. dmemcg-booster run by hand for a few seconds with the condition aside: does it turn the dmem controller on
#      along the systemd hierarchy (cgroup.subtree_control of /, system.slice, user.slice)
# Results: WORK/LABEL/console.log and the PROOF| lines in it.
set -euo pipefail
W=$(mkdir -p "$1" && readlink -f "$1"); KDEB=$(readlink -f "$2"); DEBS=$(readlink -f "$3"); LABEL=$4
HERE=$(dirname "$(readlink -f "$0")")
RIG=${RIG_IMAGE:-kernel-73-263-efi-rig:1}
OUT=$W/$LABEL; rm -rf "$OUT"; mkdir -p "$OUT"
# the system, in a throwaway forky container (apt from Debian; the edition's packages from DEBS_DIR as a flat source)
docker run --name "vram-vm-$LABEL" --platform linux/amd64 -v "$DEBS":/debs:ro -v "$KDEB":/kernel.deb:ro -v "$HERE":/t:ro debian:forky bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install systemd systemd-sysv udev kmod initramfs-tools linux-base dbus dbus-user-session libpam-systemd dpkg-dev >/dev/null
mkdir -p /flat && cp /debs/*.deb /flat/ && (cd /flat && dpkg-scanpackages . > Packages 2>/dev/null)
echo "deb [trusted=yes] file:/flat ./" > /etc/apt/sources.list.d/flat.list
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install dmemcg-booster sparky-stereo-vram-boost >/dev/null
dpkg -i /kernel.deb >/dev/null
install -m 755 /t/vm-inner.sh /usr/local/sbin/vram-proof
printf "[Unit]\nDescription=VRAM boost proof\nAfter=multi-user.target dmemcg-booster-system.service\n[Service]\nType=oneshot\nStandardOutput=journal+console\nExecStart=/usr/local/sbin/vram-proof\nExecStartPost=/usr/bin/systemctl poweroff\n[Install]\nWantedBy=multi-user.target\n" > /etc/systemd/system/vram-proof.service
systemctl enable vram-proof.service >/dev/null 2>&1
echo "root:x:0:0:root:/root:/bin/bash" >/dev/null
printf "/dev/vda / ext4 rw 0 1\n" > /etc/fstab
dpkg-query -W -f="\${Package} \${Version}\n" dmemcg-booster sparky-stereo-vram-boost systemd linux-image-* 2>/dev/null
' > "$OUT/build.log" 2>&1
docker export "vram-vm-$LABEL" > "$W/$LABEL-rootfs.tar"
docker rm "vram-vm-$LABEL" >/dev/null
# the disk, as root in the rig image so that the files keep their owners, then handed back
docker run --rm --platform linux/amd64 --cpus 2 -e OWNER="$(id -u):$(id -g)" -v "$W:$W" "$RIG" bash -c '
set -e
cd "$1"; mkdir -p root-$2; tar -xf "$2-rootfs.tar" -C root-$2 --exclude=dev/* 2>/dev/null || true
k=$(ls root-$2/boot/vmlinuz-* | head -1); i=$(ls root-$2/boot/initrd.img-* | head -1)
cp "$k" "$2/vmlinuz"; cp "$i" "$2/initrd.img"
mke2fs -q -t ext4 -d root-$2 -L root "$2/disk.img" 3G
rm -rf root-$2 "$2-rootfs.tar"; chown -R "$OWNER" "$2"
' x "$W" "$LABEL"
docker run --rm --platform linux/amd64 --cpus 2 --memory 4g --user "$(id -u):$(id -g)" --device /dev/kvm --group-add "$(getent group kvm | cut -d: -f3)" \
	-v "$W:$W" "$RIG" bash -c '
set -e
cd "$1"
timeout 600 qemu-system-x86_64 -enable-kvm -machine q35 -m 3072 -smp 2 -display none -no-reboot \
	-kernel "$2/vmlinuz" -initrd "$2/initrd.img" -append "root=/dev/vda rw console=ttyS0 systemd.show_status=0" \
	-drive file="$2/disk.img",format=raw,if=virtio -serial file:"$2/console.log" || echo "qemu exit $?"
rm -f "$2/disk.img"
' x "$W" "$LABEL"
grep -ao 'PROOF|.*' "$OUT/console.log" | tee "$OUT/proof.txt" | grep -q 'PROOF|done' || { echo "no PROOF|done line; see $OUT/console.log"; exit 1; }
