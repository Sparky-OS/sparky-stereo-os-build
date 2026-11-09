#!/bin/sh
# Every way the edition's GRUB configuration can make GRUB print an error, booted in QEMU (OVMF) with a generated grub.cfg
# (fixture-grub.cfg); the messages are GRUB's own, read from the serial port, and compared with expected.txt.
#   run-tests.sh IMAGE KERNEL ART.png [CASE...]
# IMAGE: a container image with grub-efi-amd64-bin, qemu-system-x86, ovmf, mtools, fdisk, e2fsprogs and python3.
# KERNEL: any x86 Linux kernel image (the host's /boot/vmlinuz-* does). ART.png: any PNG. Needs DOCKER_HOST set to the lane's socket.
# EXPECTATION_FROM=CASE compares each result with that case's expectation instead (the control: a wrong expectation is red).
set -eu
IMAGE=$1; KERNEL=$2; ART=$3; shift 3
HERE=$(cd "$(dirname "$0")" && pwd)
W=${SPARKY_GRUB_WORK:?set SPARKY_GRUB_WORK to a scratch folder}
mkdir -p "$W"
cp "$HERE/mkcase.py" "$HERE/boot-one.sh" "$HERE/fixture-grub.cfg" "$W/"; cp "$KERNEL" "$W/kernel"; cp "$ART" "$W/art.png"
cases=${*:-$(grep -v '^#' "$HERE/expected.txt" | cut -d'|' -f1 | tr -d ' ')}
fail=0
for c in $cases; do
	docker run --rm --ulimit core=0 --network none --user "$(id -u):$(id -g)" -v "$W:/work" "$IMAGE" sh /work/boot-one.sh "$c" > "$W/log-$c.txt" 2>&1 || { echo "FAIL $c: the guest did not run, see $W/log-$c.txt"; fail=$((fail + 1)); continue; }
	python3 -I "$HERE/check.py" "$HERE/expected.txt" "${EXPECTATION_FROM:-$c}" "$W/out/$c/serial.log" "$c" || fail=$((fail + 1))
done
echo "$fail failing"
[ "$fail" = 0 ]
