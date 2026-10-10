#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Guest only, root: compress the same real anonymous memory with each zram
# algorithm (a fresh zram device each, written and read back with direct
# I/O, so the kernel compresses in dd's own context) and report CPU time per
# page and the compression ratio from mm_stat.
#   zram-algorithms.sh UID LIMIT_MIB [algorithms...]
set -u
export LC_ALL=C
uid=$1 limit=$2
shift 2
algorithms=${*:-lz4 zstd}
here=$(cd "$(dirname "$0")" && pwd)
data=/dev/shm/anon.img
bytes=$(python3 "$here/anon-dump.py" "$uid" "$data" "$limit")
pages=$((bytes / 4096))
mhz=$(awk -F: '/^cpu MHz/ { print int($2); exit }' /proc/cpuinfo)
model=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)
echo "{\"pages\": $pages, \"cpu\": \"$model\", \"cpu_mhz\": $mhz, \"results\": ["
first=1
TIMEFORMAT='%3R %3U %3S'
for algorithm in $algorithms; do
	for run in 1 2 3; do
		id=$(cat /sys/class/zram-control/hot_add)
		dev=/sys/block/zram$id
		if ! echo "$algorithm" >$dev/comp_algorithm; then
			echo "$id" >/sys/class/zram-control/hot_remove
			echo "no $algorithm in this kernel" >&2
			continue
		fi
		echo $((bytes + (64 << 20))) >$dev/disksize
		write=$( { time dd if=$data of=/dev/zram$id bs=1M oflag=direct status=none; } 2>&1)
		read -r orig compr used _ _ same _ <$dev/mm_stat
		read_back=$( { time dd if=/dev/zram$id of=/dev/null bs=1M iflag=direct status=none; } 2>&1)
		echo 1 >$dev/reset
		echo "$id" >/sys/class/zram-control/hot_remove
		set -- $write
		wsys=$3 wreal=$1
		set -- $read_back
		rsys=$3 rreal=$1
		((first)) || echo ","
		first=0
		printf '{"algorithm": "%s", "run": %d, "write_real_s": %s, "write_sys_s": %s, "read_real_s": %s, "read_sys_s": %s, "orig_bytes": %s, "compr_bytes": %s, "mem_used_bytes": %s, "same_pages": %s}' \
			"$algorithm" "$run" "$wreal" "$wsys" "$rreal" "$rsys" "$orig" "$compr" "$used" "$same"
	done
done
echo "]}"
rm -f $data
