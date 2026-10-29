#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# run.sh BZIMAGE IGT_ROOT OUT [IGT ARGUMENTS...]
#   Boots BZIMAGE (built from the series with kconfig.fragment on tinyconfig) in QEMU, headless, with KVM when
#   /dev/kvm is usable, builds the VKMS device of init.sh (two DisplayPort connectors reading dp-fs.bin, one opted
#   in to frame-sequential stereo) and runs each subtest of IGT's kms_frame_sequential from IGT_ROOT
#   (build-igt-root.sh), passing IGT ARGUMENTS (--swap-eyes for the negative control). Writes OUT/console.log,
#   the IGT logs, the stereo link logs and OUT/dp-fs.decode.txt; check.py OUT reads them.
# Runs inside an image with qemu-system-x86, busybox-static, cpio, edid-decode and python3 (the lane's bench
# image), as the invoking user; nothing touches the host's displays. VKMS only ever runs in the guest.
set -euo pipefail
K=$(readlink -f "$1"); ROOT=$(readlink -f "$2"); OUT=$(mkdir -p "$3" && readlink -f "$3"); shift 3
HERE=$(dirname "$(readlink -f "$0")")
IGT_ARGS=$(IFS=,; echo "$*")
KVM=()
if [ -w /dev/kvm ]; then KVM=(--device /dev/kvm --group-add "$(getent group kvm | cut -d: -f3)"); fi
exec docker run --rm --platform linux/amd64 --cpus "${CPUS:-4}" --memory 6g --user "$(id -u):$(id -g)" -e HOME=/tmp \
	"${KVM[@]}" -v "$HERE":/t:ro -v "$K":/bzImage:ro -v "$ROOT":/root-igt:ro -v "$OUT":/out \
	"${IMAGE:-dp-stereo-257-m3-bench:1}" sh -euc '
	W=$(mktemp -d)
	mkdir -p $W/i/bin $W/i/data $W/i/proc $W/i/sys $W/i/dev $W/i/tmp
	cp /bin/busybox $W/i/bin/busybox
	cp /t/init.sh $W/i/init
	python3 -I /t/make-edid.py $W/i/data/dp-fs.bin
	cmp $W/i/data/dp-fs.bin /t/dp-fs.bin
	edid-decode --check /t/dp-fs.bin > /out/dp-fs.decode.txt 2>&1 || true
	(cd $W/i && find . | cpio -o -H newc --quiet | gzip -9) > $W/initramfs.gz
	accel=tcg; cpu=max
	if [ -w /dev/kvm ]; then accel=kvm; cpu=host; fi
	timeout ${TIMEOUT:-900} qemu-system-x86_64 -machine q35 -accel $accel -cpu $cpu -smp 4 -m 3072 \
		-display none -monitor none -serial stdio -no-reboot \
		-kernel /bzImage -initrd $W/initramfs.gz \
		-virtfs local,path=/out,mount_tag=out,security_model=none,id=out \
		-virtfs local,path=/root-igt,mount_tag=root,security_model=none,readonly=on,id=root \
		-append "console=ttyS0 panic=-1 loglevel=7 vkms.create_default_dev=0 kunit.enable=0 fs.args='"$IGT_ARGS"'" \
		> /out/console.log 2>&1 || echo "FS|error|qemu exit $?" >> /out/console.log
	rm -rf $W'
