#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# run.sh IMAGE_DEB OUT : the guest side of the virtio-gpu stereo command (series groups 33 and 34) on a built kernel.
# Inside an image with the edition's QEMU (virtio-gpu-pci property stereo), gcc with a static libc, busybox-static and kmod
# (the EFI mixed rig image has all of them), as the invoking user, with /dev/kvm. Boots the kernel twice, headless:
#   stereo=on   the probe must list 3D modes, every 3D set must succeed and QEMU must trace SET_SCANOUT_STEREO with that layout,
#               and the last (2D) set must trace layout 0
#   stereo=off  the control: no 3D mode listed, no stereo command traced
# check.py compares the two runs; exit status 1 when a check fails.
# VIRTIO_GPU_KO=path boots the image's kernel with that virtio-gpu.ko instead of its own (a driver fix tried before a kernel build).
set -euo pipefail
DEB=$(readlink -f "$1"); OUT=$(mkdir -p "$2" && readlink -f "$2"); HERE=$(dirname "$(readlink -f "$0")")
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
dpkg-deb -x "$DEB" "$W/img"
REL=$(basename "$(ls -d "$W"/img/lib/modules/*)")
depmod -b "$W/img" "$REL"
mkdir -p "$W/root/bin" "$W/root/mod" "$W/root/dev" "$W/root/proc" "$W/root/sys"
cp /bin/busybox "$W/root/bin/busybox"
gcc -O2 -static -o "$W/root/bin/stereo-scanout" "$HERE/stereo-scanout.c"
n=0
for m in virtio_pci virtio_gpu; do
	modprobe -d "$W/img" -S "$REL" --show-depends "$m" | awk '$1 == "insmod" {print $2}'
done | awk '!seen[$0]++' | while read -r ko; do
	n=$((n + 1)); name=$(printf '%02d-%s' "$n" "$(basename "$ko" | sed 's/\.xz$//; s/\.zst$//')")
	case "$ko" in
	*.xz) xz -dc "$ko" > "$W/root/mod/$name" ;;
	*.zst) zstd -qdc "$ko" > "$W/root/mod/$name" ;;
	*) cp "$ko" "$W/root/mod/$name" ;;
	esac
done
if [ -n "${VIRTIO_GPU_KO:-}" ]; then
	cp "$VIRTIO_GPU_KO" "$(ls "$W"/root/mod/*-virtio-gpu.ko)"
fi
cat > "$W/root/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
for m in /mod/*.ko; do insmod "$m" 2>/dev/null || echo "INSMOD|$m|failed"; done
i=0; while [ ! -e /dev/dri/card0 ] && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done
echo "KERNEL|$(uname -r)"
/bin/stereo-scanout
poweroff -f
INIT
chmod 755 "$W/root/init"
(cd "$W/root" && find . | cpio -o -H newc --quiet | gzip -1) > "$W/initrd.img"
for s in on off; do
	timeout 180 qemu-system-x86_64 -enable-kvm -machine q35 -m 2048 -smp 2 -display none -no-reboot \
		-kernel "$W/img/boot/vmlinuz-$REL" -initrd "$W/initrd.img" -append "console=ttyS0 panic=-1 loglevel=4" \
		-device "virtio-gpu-pci,stereo=$s,edid=on" -serial "file:$OUT/guest-stereo-$s.log" \
		-d trace:virtio_gpu_cmd_set_scanout_stereo -D "$OUT/qemu-stereo-$s.log" || echo "qemu exit $? (stereo=$s)"
done
python3 -I "$HERE/check.py" "$OUT"
