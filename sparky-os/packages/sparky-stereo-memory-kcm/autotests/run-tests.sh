#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# As an ordinary user: the page reads the files under a fixture root, with
# the real zram-auto (ZRAM_AUTO = its path) deciding for a 96 GB NVMe and a
# 4 GB eMMC fixture. BUILD is the build tree.
set -u
BUILD=${BUILD:?build tree}
OUT=${OUT:?results folder}
mkdir -p "$OUT"
W=$(mktemp -d "${TMPDIR:-/tmp}/memory-kcm.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/root/usr/libexec/sparky-stereo" "$W/sys/devices/nvme0n1/queue" "$W/sys/devices/mmcblk0/queue" "$W/sys/devices/mmcblk0/device" "$W/sys/dev/block"
install -m755 "${ZRAM_AUTO:?zram-auto}" "$W/root/usr/libexec/sparky-stereo/zram-auto"
echo 0 >"$W/sys/devices/nvme0n1/queue/rotational"
echo 0 >"$W/sys/devices/mmcblk0/queue/rotational"
echo MMC >"$W/sys/devices/mmcblk0/device/type"
ln -s "$W/sys/devices/nvme0n1" "$W/sys/dev/block/259:0"
ln -s "$W/sys/devices/mmcblk0" "$W/sys/dev/block/179:0"
status=0
run() {
	local name=$1 kib=$2 devno=$3
	printf 'MemTotal: %s kB\n' "$kib" >"$W/meminfo"
	env SPARKY_STEREO_MEMORY_ROOT="$W/root" MEMINFO_PATH="$W/meminfo" SYSFS_PATH="$W/sys" ZRAM_AUTO_DEVNO="$devno" \
		CUSHION_SWAP_CONFIG=/nonexistent FSTAB_PATH=/nonexistent EXPECT_AUTO="$4" EXPECT_REASON="$5" QT_QPA_PLATFORM=offscreen \
		"$BUILD/bin/memorykcmtest" >"$OUT/$name.log" 2>&1 || status=1
	tail -n 3 "$OUT/$name.log"
}
run nvme-96GB 97957892 259:0 off "95662 MiB of RAM and the swap area on fast storage"
run emmc-4GB 4073000 179:0 on "3977 MiB of RAM: 8 GB or less"
exit $status
