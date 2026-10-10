#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# zram by hardware, in a container as an ordinary user: zram-auto against
# sysfs fixtures, then the real zram-generator (ZRAM_GENERATOR = its binary,
# zram-auto bind-mounted at /usr/libexec/sparky-stereo/zram-auto) on the
# packaged configuration. The 96 GB NVMe machine must get no zram unit (the
# control); the 4 GB eMMC machine must get one.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "$HERE")
AUTO=$PKG/usr/libexec/sparky-stereo/zram-auto
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/zram-auto-results.XXXXXX")}
W=$(mktemp -d "${TMPDIR:-/tmp}/zram-auto.XXXXXX")
trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
PASS=0 FAIL=0
check() {
	if [[ $2 == "$3" ]]; then
		echo "PASS $1"
		PASS=$((PASS + 1))
	else
		echo "FAIL $1: got '$2', expected '$3'"
		FAIL=$((FAIL + 1))
	fi
}

# sysfs fixture: /sys/dev/block/MAJ:MIN -> a disk or partition node
S=$W/sys
disk() {
	local devno=$1 path=$2 rotational=$3 removable=$4 type=${5:-}
	mkdir -p "$S/$path/queue" "$S/dev/block"
	echo "$rotational" >"$S/$path/queue/rotational"
	echo "$removable" >"$S/$path/removable"
	echo "$devno" >"$S/$path/dev"
	if [[ -n $type ]]; then
		mkdir -p "$S/$path/device"
		echo "$type" >"$S/$path/device/type"
	fi
	ln -s "$S/$path" "$S/dev/block/$devno"
}
part() {
	local devno=$1 path=$2
	mkdir -p "$S/$path"
	echo 1 >"$S/$path/partition"
	echo "$devno" >"$S/$path/dev"
	ln -s "$S/$path" "$S/dev/block/$devno"
}
disk 259:0 devices/pci0000:00/nvme/nvme0/nvme0n1 0 0
part 259:2 devices/pci0000:00/nvme/nvme0/nvme0n1/nvme0n1p2
disk 179:0 devices/platform/mmc_host/mmc0/mmc0:0001/block/mmcblk0 0 0 MMC
part 179:2 devices/platform/mmc_host/mmc0/mmc0:0001/block/mmcblk0/mmcblk0p2
disk 179:32 devices/platform/mmc_host/mmc1/mmc1:aaaa/block/mmcblk1 0 1 SD
disk 8:0 devices/pci0000:00/ata1/host0/target0:0:0/0:0:0:0/block/sda 1 0
disk 8:16 devices/pci0000:00/usb1/1-1/1-1:1.0/host2/target2:0:0/2:0:0:0/block/sdb 0 1
disk 8:32 devices/pci0000:00/ata2/host1/target1:0:0/1:0:0:0/block/sdc 0 0
disk 253:0 devices/virtual/block/dm-0 0 0
mkdir -p "$S/devices/virtual/block/dm-0/slaves"
ln -s "$S/devices/platform/mmc_host/mmc0/mmc0:0001/block/mmcblk0/mmcblk0p2" "$S/devices/virtual/block/dm-0/slaves/mmcblk0p2"

ram() { printf 'MemTotal: %s kB\nMemAvailable: 1000 kB\n' "$1" >"$W/meminfo"; }
auto() {
	env SYSFS_PATH="$S" MEMINFO_PATH="$W/meminfo" SPARKY_ZRAM_CONFIG="${CONF:-/nonexistent}" \
		CUSHION_SWAP_CONFIG=/nonexistent FSTAB_PATH=/nonexistent ZRAM_AUTO_DEVNO="$1" sh "$AUTO" ${2:-}
}

# RAM: 4, 8, 16 and 96 GB (MemTotal at Daniel's MemTotal/nominal ratio)
while read -r gb kib devno kind expected; do
	ram "$kib"
	check "auto-${gb}GB-$kind" "$(auto "$devno")" "$expected"
done <<'CASES'
4 4073000 259:2 nvme 1
8 8159000 259:2 nvme 1
16 16326000 259:2 nvme 0
96 97957892 259:2 nvme 0
96 97957892 179:2 emmc 1
16 16326000 179:2 emmc 1
4 4073000 179:2 emmc 1
16 16326000 179:32 sd-card 1
16 16326000 8:0 rotating 1
16 16326000 8:16 usb-removable 1
16 16326000 8:32 sata-ssd 0
16 16326000 253:0 luks-on-emmc 1
CASES
ram 97957892
check explain-96GB-nvme "$(auto 259:2 --explain | tr '\n' ' ')" "DECISION=off MODE=auto REASON=95662 MiB of RAM and the swap area on fast storage RAM_KIB=97957892 STORAGE=fast "
ram 4073000
check explain-4GB-emmc "$(auto 179:2 --explain | sed -n 's/^REASON=//p')" "3977 MiB of RAM: 8 GB or less"
printf 'ZRAM=on\n' >"$W/on"
printf 'ZRAM="off" # the user\n' >"$W/off"
ram 97957892
check override-on-96GB "$(CONF=$W/on auto 259:2)" 1
ram 4073000
check override-off-4GB "$(CONF=$W/off auto 179:2)" 0
check override-off-reason "$(CONF=$W/off auto 179:2 --explain | sed -n 's/^REASON=//p')" "switched off in $W/off"

# The real zram-generator on the packaged configuration.
if [[ -n ${ZRAM_GENERATOR:-} ]]; then
	gen() {
		local kib=$1 devno=$2 root=$W/root
		rm -rf "$root" "$W/units"
		mkdir -p "$root/proc" "$root/usr/lib/systemd/zram-generator.conf.d" "$W/units"
		cp "$PKG/usr/lib/systemd/zram-generator.conf.d/50-sparky-stereo.conf" "$root/usr/lib/systemd/zram-generator.conf.d/"
		# Debian's systemd-zram-generator turns zram0 on by default with this file
		printf '[zram0]\n' >"$root/usr/lib/systemd/zram-generator.conf"
		printf 'MemTotal: %s kB\nMemAvailable: 1000 kB\n' "$kib" >"$root/proc/meminfo"
		echo 'BOOT_IMAGE=/vmlinuz root=UUID=1 ro quiet' >"$root/proc/cmdline"
		env ZRAM_GENERATOR_ROOT="$root" SYSFS_PATH="$S" MEMINFO_PATH="$root/proc/meminfo" SPARKY_ZRAM_CONFIG="${CONF:-/nonexistent}" \
			CUSHION_SWAP_CONFIG=/nonexistent FSTAB_PATH=/nonexistent ZRAM_AUTO_DEVNO="$devno" \
			"$ZRAM_GENERATOR" "$W/units" >"$W/gen.log" 2>&1
		find "$W/units" -type f -name '*.swap' -printf '%f\n' | sort | tr '\n' ' '
		grep -h -o 'with [0-9]*MB' "$W/gen.log" | tr '\n' ' '
	}
	check generator-96GB-nvme-no-unit "$(gen 97957892 259:2)" ""
	rm -f "$W/root/usr/lib/systemd/zram-generator.conf.d/50-sparky-stereo.conf"
	env ZRAM_GENERATOR_ROOT="$W/root" "$ZRAM_GENERATOR" "$W/units" >/dev/null 2>&1
	check control-debian-default-alone-makes-zram "$(find "$W/units" -type f -name '*.swap' -printf '%f\n')" dev-zram0.swap
	check generator-4GB-emmc-unit "$(gen 4073000 179:2)" "dev-zram0.swap with 3977MB "
	check generator-16GB-rotating-unit "$(gen 16326000 8:0)" "dev-zram0.swap with 8192MB "
	check generator-16GB-nvme-no-unit "$(gen 16326000 259:2)" ""
	check generator-96GB-switched-on "$(CONF=$W/on gen 97957892 259:2)" "dev-zram0.swap with 8192MB "
	check generator-4GB-switched-off "$(CONF=$W/off gen 4073000 179:2)" ""
	gen 4073000 179:2 >/dev/null
	check generator-algorithm "$(sed -n 's/.*compression-algorithm.*/&/p' "$PKG/usr/lib/systemd/zram-generator.conf.d/50-sparky-stereo.conf")" "compression-algorithm = lz4"
	check generator-priority-100 "$(grep -c '^swap-priority = 100$' "$PKG/usr/lib/systemd/zram-generator.conf.d/50-sparky-stereo.conf")" 1
	cp "$W/gen.log" "$OUT/zram-generator-4GB-emmc.log"
fi
# Planted faults: zram on capable machines, or the storage rule lost.
mutant() {
	local name=$1 expr=$2 devno=$3 kib=$4 expected=$5 m=$W/zram-auto-$1
	sed "$expr" "$AUTO" >"$m"
	ram "$kib"
	local got
	got=$(env SYSFS_PATH="$S" MEMINFO_PATH="$W/meminfo" SPARKY_ZRAM_CONFIG=/nonexistent CUSHION_SWAP_CONFIG=/nonexistent \
		FSTAB_PATH=/nonexistent ZRAM_AUTO_DEVNO="$devno" sh "$m")
	if ! cmp -s "$m" "$AUTO" && [[ $got != "$expected" ]]; then
		echo "PASS mutant-$name (the control catches it: got $got, the right answer is $expected)"
		PASS=$((PASS + 1))
	else
		echo "FAIL mutant-$name"
		FAIL=$((FAIL + 1))
	fi
}
mutant always-on 's/decision=0 reason=/decision=1 reason=/' 259:2 97957892 0
mutant no-storage-rule 's/emmc | sd-card | rotating | removable | usb)/no-such-kind)/' 179:2 97957892 1
echo "SUMMARY: $PASS passed, $FAIL failed" | tee "$OUT/summary.txt"
((FAIL == 0))
