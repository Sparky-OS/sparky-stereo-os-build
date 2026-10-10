#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Guest only, as root, on a 4 GB machine where Automatic switched zram on,
# swappiness 1, no other swap: grow compressible memory 1.5 GiB past what is
# available. With zram the allocation completes and zram holds the excess;
# the control (zram switched off) reaches the OOM killer.
#   zram-pressure.sh MEMGROW OUT
set -u
memgrow=$1 out=$2
shift 2
mkdir -p "$out"
run() {
	local name=$1 since avail status
	since=$(date '+%F %T')
	avail=$(awk '$1 == "MemAvailable:" { print int($2 / 1024) }' /proc/meminfo)
	systemd-run --scope -q --slice=system.slice python3 "$memgrow" 256 $((avail + 1536)) 5 mixed >"$out/$name.grow" 2>&1 &
	local pid=$! peak=0
	while kill -0 $pid 2>/dev/null; do
		read -r orig compr used _ </sys/block/zram0/mm_stat 2>/dev/null || orig=0
		((orig > peak)) && peak=$orig
		sleep 0.5
	done
	wait $pid
	status=$?
	printf '{"run": "%s", "swappiness": %s, "start_avail_mib": %s, "target_mib": %s, "allocator_status": %s, "reached": %s, "zram_peak_orig_bytes": %s, "oom_kills": %s}\n' \
		"$name" "$(cat /proc/sys/vm/swappiness)" "$avail" $((avail + 1536)) "$status" \
		"$(grep -q reached "$out/$name.grow" && echo true || echo false)" "$peak" \
		"$(journalctl -q -k --since "$since" --no-pager | grep -c 'Killed process')"
}
sync; sleep 3
[[ ${1:-} == --control-only ]] || run zram-on
for try in 1 2 3 4 5 6; do
	sleep 5
	swapoff /dev/zram0 && break
done
if grep -q /dev/zram0 /proc/swaps; then
	echo '{"run": "control-zram-off", "error": "zram could not be switched off"}'
	exit 1
fi
sync; sleep 3
run control-zram-off
swapon -p 100 /dev/zram0
