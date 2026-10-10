#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Guest only, as root, in a disposable VM with the package installed and no
# swap active: the packaged psi-wake arms its default trigger, stays quiet for
# 10 s without pressure, and reports a stall when an allocation runs the whole
# machine out of memory at 256 MiB/s (the OOM killer ends it). A memory-limited
# scope is not enough: its own OOM kill comes before 150 ms of stall.
set -u
here=$(cd "$(dirname "$0")" && pwd)
helper=/usr/libexec/cushion-swap/psi-wake
"$helper" >/var/tmp/psi-quiet.out 2>&1 &
q=$!
sleep 10
kill $q; wait $q 2>/dev/null
"$helper" >/var/tmp/psi-pressure.out 2>&1 &
p=$!
sleep 1
avail=$(awk '$1 == "MemAvailable:" { print int($2 / 1024) }' /proc/meminfo)
systemd-run --scope -q --slice=system.slice python3 "$here/memgrow.py" 256 $((avail + 3072)) 0 >/dev/null 2>&1
status=$?
sleep 2
kill $p; wait $p 2>/dev/null
quiet=$(grep -c stall /var/tmp/psi-quiet.out)
pressure=$(grep -c stall /var/tmp/psi-pressure.out)
ready=$(cat /var/tmp/psi-quiet.out /var/tmp/psi-pressure.out | grep -c ready)
echo "{\"ready\": $ready, \"stall_without_pressure_10s\": $quiet, \"stall_with_pressure\": $pressure, \"allocator_status\": $status}"
((ready == 2 && quiet == 0 && pressure > 0))
