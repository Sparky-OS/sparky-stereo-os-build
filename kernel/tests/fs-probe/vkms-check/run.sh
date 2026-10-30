#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# run.sh BZIMAGE FS_PROBE EDID OUT: boots BZIMAGE (series group 38's VKMS model, built as
# kernel/tests/vkms-frame-sequential builds it) in QEMU, headless, with
# fs-probe and init.sh in the initramfs; writes OUT/console.log. IMAGE: an image with qemu-system-x86, busybox-static
# and cpio (kernel/tests/vkms-frame-sequential's bench image).
set -euo pipefail
K=$(readlink -f "$1"); P=$(readlink -f "$2"); E=$(readlink -f "$3"); OUT=$(mkdir -p "$4" && readlink -f "$4")
HERE=$(dirname "$(readlink -f "$0")")
exec env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u XAUTHORITY \
docker run --rm --platform linux/amd64 --cpus 4 --memory 4g --user "$(id -u):$(id -g)" -e HOME=/tmp \
	--device /dev/kvm --group-add "$(getent group kvm | cut -d: -f3)" \
	-v "$HERE":/t:ro -v "$K":/bzImage:ro -v "$P":/fs-probe:ro -v "$E":/edid.bin:ro -v "$OUT":/out \
	"${IMAGE:-dp-stereo-257-m3-bench:1}" sh -euc '
	W=$(mktemp -d)
	mkdir -p $W/i/bin $W/i/data $W/i/proc $W/i/sys $W/i/dev $W/i/tmp
	cp /bin/busybox $W/i/bin/busybox
	cp /fs-probe $W/i/bin/fs-probe
	cp /t/init.sh $W/i/init
	cp /edid.bin $W/i/data/dp-fs.bin
	(cd $W/i && find . | cpio -o -H newc --quiet | gzip -9) > $W/initramfs.gz
	timeout 600 qemu-system-x86_64 -machine q35 -accel kvm -cpu host -smp 4 -m 2048 \
		-display none -monitor none -serial stdio -no-reboot \
		-kernel /bzImage -initrd $W/initramfs.gz \
		-append "console=ttyS0 panic=-1 loglevel=4 vkms.create_default_dev=0 kunit.enable=0" \
		> /out/console.log 2>&1 || echo "FS|error|qemu exit $?" >> /out/console.log
	rm -rf $W'
