#!/bin/bash
# mkinitrd.sh OUT.img : a busybox-static initramfs whose /init prints the boot facts and powers off (runs in the rig image)
set -euo pipefail
OUT=$1; HERE=$(dirname "$(readlink -f "$0")")
D=$(mktemp -d)
mkdir -p "$D/bin"
cp /bin/busybox "$D/bin/busybox"
install -m 755 "$HERE/init.sh" "$D/init"
(cd "$D" && find . | cpio -o -H newc --quiet | gzip -9) > "$OUT"
rm -rf "$D"
