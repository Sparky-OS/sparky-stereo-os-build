#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Guest only, as root, in a disposable VM: grow memory at RATE MiB/s past
# what is available and record MemAvailable, PSI events and swap use every
# 20 ms, until the allocation ends (reached, or killed by the OOM killer).
#   [JITTER_MS=N] race.sh OUTDIR RATE OVERSHOOT_MIB [system|user]
# "user" runs the allocation inside user@1000.service, where systemd-oomd
# watches memory pressure; "system" runs it in system.slice.
set -u
out=$1 rate=$2 overshoot=$3 where=${4:-system}
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
avail=$(awk '$1 == "MemAvailable:" { print int($2 / 1024) }' /proc/meminfo)
total=$((avail + overshoot))
since=$(date '+%F %T')
python3 "$here/memsample.py" "$out/sample.json" 300 "${TRIGGER:-some 150000 1000000}" &
sampler=$!
sleep 1
# JITTER_MS: a random start within the window, so the daemon's sampling phase is random too
[[ -n ${JITTER_MS:-} ]] && sleep "$(awk -v r=$RANDOM -v j="$JITTER_MS" 'BEGIN { printf "%.3f", (r % j) / 1000 }')"
start=$(date +%s.%N)
if [[ $where == user ]]; then
	runuser -u daniel -- env XDG_RUNTIME_DIR=/run/user/1000 systemd-run --user --scope -q \
		python3 "$here/memgrow.py" "$rate" "$total" 3 >"$out/grow.txt" 2>&1
else
	systemd-run --scope --slice=system.slice -q python3 "$here/memgrow.py" "$rate" "$total" 3 >"$out/grow.txt" 2>&1
fi
echo $? >"$out/grow.status"
end=$(date +%s.%N)
sleep 3
touch "$out/sample.json.stop"
wait "$sampler"
rm -f "$out/sample.json.stop"
printf 'rate=%s target_mib=%s start_avail_mib=%s where=%s started=%s seconds=%s\n' "$rate" "$total" "$avail" "$where" "$start" \
	"$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.3f", b - a }')" >"$out/run.txt"
journalctl -q -k --since "$since" --no-pager | grep -E "Out of memory|oom-kill|Killed process" >"$out/oom.txt"
journalctl -q -u systemd-oomd -u cushion-swap --since "$since" --no-pager >"$out/units.txt"
