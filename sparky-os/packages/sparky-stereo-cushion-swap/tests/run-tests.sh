#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# Cushion Swap File checks, run as an ordinary user in a container: fixtures
# for /proc, /sys, /dev/disk and /etc, fake swapon/swapoff/findmnt/filefrag
# that only record or answer, the real logrotate, Daniel's own harness, and
# planted faults that must each fail their check.
# A real PSI trigger cannot be armed in a Docker container (its AppArmor
# profile denies writing /proc/pressure/memory): guest/psi-wake-check.sh
# proves the helper in a VM. Writes results to $OUT.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(dirname "$HERE")
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/cushion-swap-results.XXXXXX")}
mkdir -p "$OUT"
exec > >(tee -a "$OUT/run.log") 2>&1
W=$(mktemp -d "${TMPDIR:-/tmp}/cushion-swap-work.XXXXXX")
trap 'rm -rf "$W"' EXIT
G=1048576
PASS=0 FAIL=0
# The files under test; a planted fault replaces one of them.
GEN=$PKG/lib/systemd/system-generators/cushion-swap-hibernate-generator
HOOK=$PKG/share/initramfs-tools/hooks/cushion-swap-resume-offset
UNIT=$PKG/lib/systemd/system/cushion-swap.service
LOGROTATE=$PKG/etc/logrotate.d/sparky-stereo-cushion-swap
TMPFILES=$PKG/lib/tmpfiles.d/cushion-swap.conf
LOG_PATH=/var/log/cushion-swap/cushion-swap.log

check() {
	local name=$1
	shift
	if "$@"; then
		echo "PASS $name"
		PASS=$((PASS + 1))
	else
		echo "FAIL $name"
		FAIL=$((FAIL + 1))
	fi
}

meminfo() {
	printf 'MemTotal:       %s kB\nMemFree:        1000 kB\nMemAvailable:   %s kB\nSwapTotal:      %s kB\nSwapFree:       %s kB\n' "$2" "$3" "${4:-0}" "${5:-0}" >"$1"
}

swaps() {
	local file=$1
	shift
	printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n' >"$file"
	while (($#)); do
		printf '%s\t\t\t\tfile\t\t%s\t\t%s\t\t-2\n' "$1" "$2" "$3" >>"$file"
		shift 3
	done
}

make_fakes() {
	mkdir -p "$W/bin" "$W/dev" "$W/disk/by-uuid" "$W/root" "$W/sys/power" "$W/empty"
	printf '#!/bin/sh\necho "swapon $*" >>"%s/actions"\n' "$W" >"$W/bin/swapon"
	printf '#!/bin/sh\necho "swapoff $*" >>"%s/actions"\n' "$W" >"$W/bin/swapoff"
	printf '#!/bin/sh\necho "swapon $*" >>"%s/actions"\nexit 1\n' "$W" >"$W/bin/swapon-fails"
	# findmnt -n -o SOURCE -T PATH: the device a fixture path lives on
	cat >"$W/bin/findmnt" <<EOF
#!/bin/sh
for a; do last=\$a; done
while read -r prefix device; do
	case \$last in "\$prefix"*) echo "\$device"; exit 0 ;; esac
done <"$W/findmnt.map"
exit 1
EOF
	# filefrag -v -bN PATH: one extent, starting where the fixture says
	cat >"$W/bin/filefrag" <<EOF
#!/bin/sh
for a; do last=\$a; done
while read -r path physical; do
	if [ "\$path" = "\$last" ]; then
		echo "Filesystem type is: ef53"
		echo " ext:     logical_offset:        physical_offset: length:   expected: flags:"
		echo "   0:        0..   4194303:    \$physical..  \$((physical + 4194303)):  4194304:             last,eof"
		exit 0
	fi
done <"$W/filefrag.map"
exit 1
EOF
	chmod +x "$W/bin/"*
	# The machine: root file system on vda2 with the Cushion area as a swap
	# file; a swap partition vdb3 that is in no fstab line (Daniel's layout).
	: >"$W/dev/vda2"
	truncate -s 16G "$W/dev/vdb3"
	truncate -s 16G "$W/root/swapfile"
	truncate -s 16G "$W/root/other-swapfile"
	ln -sf "$W/dev/vda2" "$W/disk/by-uuid/root-fs"
	ln -sf "$W/dev/vdb3" "$W/disk/by-uuid/swap-part"
	echo "$W/root/ $W/dev/vda2" >"$W/findmnt.map"
	printf '%s 34816\n%s 99000\n' "$W/root/swapfile" "$W/root/other-swapfile" >"$W/filefrag.map"
	printf '%s/root/swapfile none swap noauto 0 0\n' "$W" >"$W/fstab-area"
	echo 'BOOT_IMAGE=/vmlinuz root=UUID=root-fs ro quiet' >"$W/cmdline-plain"
	echo 0:0 >"$W/sys/power/resume"
	echo 0 >"$W/sys/power/resume_offset"
}

build_helper() {
	gcc -O2 -Wall -Wextra -Werror -o "$W/psi-wake" "$PKG/src/psi-wake.c"
}

# Daemon environment for fixture runs; background runs exec the daemon so
# that its PID is the one the test stops.
ENV_COMMON=()
set_env() {
	ENV_COMMON=(CUSHION_SWAP_CONFIG=/nonexistent STATE_DIR="$W/state" SWAPON_BIN="$W/bin/swapon" SWAPOFF_BIN="$W/bin/swapoff"
		PSI_WAKE="$W/psi-wake" INITRAMFS_RESUME_PATH=/nonexistent CMDLINE_PATH="$W/cmdline-plain" DEV_DISK_DIR="$W/disk"
		SYS_POWER_DIR="$W/sys/power" SYS_BLOCK_DIR="$W/empty" FINDMNT_BIN="$W/bin/findmnt" FILEFRAG_BIN="$W/bin/filefrag")
}

daemon() {
	env "${ENV_COMMON[@]}" FSTAB_PATH="${FSTAB:-/nonexistent}" "$@"
}

daemon_bg() {
	local log=$1 journal=$2
	shift 2
	(exec env "${ENV_COMMON[@]}" FSTAB_PATH=/nonexistent "$@" >>"$log" 2>>"$journal") &
	BG_PID=$!
}

stop_bg() {
	kill "$BG_PID" 2>/dev/null
	wait "$BG_PID" 2>/dev/null
	! kill -0 "$BG_PID" 2>/dev/null
}

samples() {
	grep -c 'sample:' "$1"
}

threshold_cases() {
	local d=$1 gb total expected out ok=0
	# MemTotal: 96 GB is Daniel's machine (his fixture); the others keep its MemTotal/nominal ratio.
	while read -r gb total expected; do
		meminfo "$W/m$gb" "$total" $((40 * G))
		out=$(daemon MEMINFO_PATH="$W/m$gb" "$d" --thresholds | sed -n 's/^DEPLOY_HARD_KIB=\([0-9]*\) DEPLOY_SOFT_KIB=\([0-9]*\) RATE_KIB=\([0-9]*\) RETRACT_MARGIN_KIB=\([0-9]*\)$/\1 \2 \3 \4/p')
		if [[ $out != "$expected" ]]; then
			echo "  ${gb} GB: got '$out', expected '$expected'"
			ok=1
		fi
		echo "$gb $total $out" >>"$OUT/thresholds.txt"
	done <<EOF
4 4073000 271533 543066 45255 905111
8 8159000 543933 1087866 90655 1813111
16 16326000 1088400 2176800 181400 3628000
32 32654000 2176933 4353866 362822 7256444
64 65307000 4353800 8707600 725633 14512666
96 97957892 6291456 12582912 1048576 20971520
EOF
	return $ok
}

reference_unchanged() {
	meminfo "$W/m96" 97957892 $((40 * G))
	daemon MEMINFO_PATH="$W/m96" "$1" --thresholds | grep -qx 'deploy_hard=6.00GiB deploy_soft=12.00GiB rate=1.00GiB/10s retract_margin=20.00GiB quiet=600s'
}

settings_win() {
	printf 'DEPLOY_HARD_MIB=1000\n# a comment\nRETRACT_MARGIN_GIB=3\n' >"$W/conf"
	meminfo "$W/m4" 4073000 $((2 * G))
	env CUSHION_SWAP_CONFIG="$W/conf" MEMINFO_PATH="$W/m4" FSTAB_PATH=/nonexistent "$1" --thresholds |
		grep -q '^DEPLOY_HARD_KIB=1024000 DEPLOY_SOFT_KIB=543066 RATE_KIB=45255 RETRACT_MARGIN_KIB=3145728$'
}

# Deploy at the floor, one area only, with zram already active.
deploy_own_area_only() {
	local d=$1
	rm -f "$W/actions" "$W/state/state"
	meminfo "$W/m" 97957892 $((4 * G)) $((8 * G)) $((8 * G))
	swaps "$W/s" /dev/zram0 8388608 0
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1000 "$d" --once >"$W/log" 2>&1
	[[ $(cat "$W/actions" 2>/dev/null) == "swapon -- /swapfile" ]]
}

deploy_on_rate() {
	local d=$1
	rm -f "$W/actions" "$W/state/state"
	swaps "$W/s"
	meminfo "$W/m" 16326000 $((3 * G))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH_MS=2000000 "$d" --once >/dev/null 2>&1
	# 16 GB: soft floor 2.08 GiB, rate 177 MiB/10 s; 500 MiB in 1.5 s is far above it.
	meminfo "$W/m" 16326000 $((2 * G - 500 * 1024))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH_MS=2001500 "$d" --once >"$W/log" 2>&1
	grep -q 'rate_trigger=1' "$W/log" && [[ $(cat "$W/actions" 2>/dev/null) == "swapon -- /swapfile" ]]
}

no_deploy_above_floor() {
	local d=$1
	rm -f "$W/actions" "$W/state/state"
	swaps "$W/s"
	meminfo "$W/m" 16326000 $((3 * G))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1000 "$d" --once >/dev/null 2>&1
	[[ ! -e $W/actions ]]
}

retract_own_area_only() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	mkdir -p "$W/state"
	printf '0 0 1000 0\n' >"$W/state/state"
	meminfo "$W/m" 97957892 $((40 * G)) $((16 * G)) $((14 * G))
	swaps "$W/s" /dev/zram0 8388608 0 /swapfile 8388608 2097152
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ $(cat "$W/actions" 2>/dev/null) == "swapoff -- /swapfile" ]]
}

no_retract_under_pressure() {
	local d=$1
	rm -f "$W/actions"
	mkdir -p "$W/state"
	printf '0 0 1650 0\n' >"$W/state/state"
	meminfo "$W/m" 97957892 $((40 * G)) $((16 * G)) $((14 * G))
	swaps "$W/s" /swapfile 16777216 2097152
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/actions ]] && grep -q 'quiet_pass=no' "$W/log"
}

no_retract_without_margin() {
	local d=$1
	rm -f "$W/actions"
	mkdir -p "$W/state"
	printf '0 0 1000 0\n' >"$W/state/state"
	# 12 GiB in swap needs more than 32 GiB available; 30 GiB is not enough.
	meminfo "$W/m" 97957892 $((30 * G)) $((16 * G)) $((4 * G))
	swaps "$W/s" /swapfile 16777216 12582912
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/actions ]] && grep -q 'margin_pass=no' "$W/log"
}

# Daniel, 2026-10-10: an area that is on and was never used goes off after
# the quiet window, and only then.
retract_unused_area() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	mkdir -p "$W/state"
	printf '0 0 1000 0\n' >"$W/state/state"
	meminfo "$W/m" 16326000 $((10 * G)) $((16 * G)) $((16 * G))
	swaps "$W/s" /swapfile 16777216 0
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ $(cat "$W/actions" 2>/dev/null) == "swapoff -- /swapfile" ]] && grep -q 'area_empty=yes hibernating=no => retract_ok=1' "$W/log"
}

no_retract_unused_area_before_quiet() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	mkdir -p "$W/state"
	printf '0 0 1650 0\n' >"$W/state/state"
	meminfo "$W/m" 16326000 $((10 * G)) $((16 * G)) $((16 * G))
	swaps "$W/s" /swapfile 16777216 0
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/actions ]] && grep -q 'area_empty=yes hibernating=no => retract_ok=0' "$W/log"
}

# The hibernate unit has switched the area on for the image: no retraction
# until the sleep hook runs, or the hold has expired (a hibernation that
# never started).
no_retract_while_hibernating() {
	local d=$1 ok=0
	rm -f "$W/actions"
	mkdir -p "$W/state"
	printf '0 0 1000 0\n' >"$W/state/state"
	printf '1690 /swapfile 1\n' >"$W/state/hibernate-deployed"
	meminfo "$W/m" 16326000 $((10 * G)) $((16 * G)) $((16 * G))
	swaps "$W/s" /swapfile 16777216 0
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/actions ]] && grep -q 'hibernating=yes => retract_ok=0' "$W/log" || { echo "  retracted during a hibernation"; ok=1; }
	printf '1000 /swapfile 1\n' >"$W/state/hibernate-deployed"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ $(cat "$W/actions" 2>/dev/null) == "swapoff -- /swapfile" ]] || { echo "  a stale hold kept the area on"; ok=1; }
	rm -f "$W/state/hibernate-deployed"
	return $ok
}

fstab_noauto_only() {
	local d=$1
	rm -f "$W/actions" "$W/state/state"
	printf '# test\nUUID=1 / ext4 defaults 0 1\n/dev/sda9 none swap sw 0 0\n/swap/cushion none swap noauto,pri=-5 0 0\n' >"$W/fstab"
	meminfo "$W/m" 97957892 $((4 * G))
	swaps "$W/s"
	FSTAB=$W/fstab daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" NOW_EPOCH=1000 "$d" --once >"$W/log" 2>&1
	[[ $(cat "$W/actions" 2>/dev/null) == "swapon -- /swap/cushion" ]]
}

no_area_no_action() {
	local d=$1
	rm -f "$W/actions" "$W/state/state"
	printf '/dev/sda9 none swap sw 0 0\n' >"$W/fstab"
	meminfo "$W/m" 97957892 $((4 * G))
	swaps "$W/s"
	FSTAB=$W/fstab daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" NOW_EPOCH=1000 "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/actions ]] && grep -q 'no Cushion Swap File area is configured' "$W/log"
}

switched_off() {
	local d=$1
	rm -f "$W/actions"
	printf 'CUSHION_SWAP=off\n' >"$W/conf"
	meminfo "$W/m" 97957892 $((4 * G))
	swaps "$W/s"
	env CUSHION_SWAP_CONFIG="$W/conf" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile STATE_DIR="$W/state" \
		SWAPON_BIN="$W/bin/swapon" SWAPOFF_BIN="$W/bin/swapoff" "$d" --once >"$W/log" 2>&1
	[[ $? == 0 && ! -e $W/actions ]] && grep -q 'Cushion Swap File is off' "$W/log"
}

# --- Logging (Daniel, 2026-10-10) -----------------------------------------
# The unit appends standard output to the log file and sends standard error
# to the journal; here two files stand for them.

every_cycle_by_default() {
	local d=$1 ok=0 cycles
	rm -rf "$W/state" "$W/lg"
	mkdir -p "$W/lg"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon_bg "$W/lg/file" "$W/lg/journal" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile PSI=off PACING=fixed POLL_INTERVAL_SEC=0.1 "$d"
	sleep 1.5
	stop_bg || ok=1
	cycles=$(samples "$W/lg/file")
	((cycles >= 8)) || { echo "  $cycles cycles in the file in 1.5 s"; ok=1; }
	grep -q 'retract-check: .* => retract_ok=0' "$W/lg/file" || { echo "  no arithmetic in the file"; ok=1; }
	grep -qE 'sample:|deploy-check:|retract-check:' "$W/lg/journal" && { echo "  per-cycle lines reached the journal"; ok=1; }
	grep -q 'cushion-swap: starting' "$W/lg/journal" && grep -q 'thresholds (reference' "$W/lg/journal" ||
		{ echo "  the startup lines are not in the journal"; ok=1; }
	# cycle numbers: consecutive in the file
	grep -o 'cycle=[0-9]*' "$W/lg/file" | cut -d= -f2 | awk 'NR > 1 && $1 != prev + 1 { bad = 1 } { prev = $1 } END { exit bad }' ||
		{ echo "  cycle numbers not consecutive"; ok=1; }
	return $ok
}

actions_in_both() {
	local d=$1 ok=0 f=$W/act/file j=$W/act/journal
	rm -rf "$W/act" "$W/actions" "$W/state"
	mkdir -p "$W/act" "$W/state"
	swaps "$W/s"
	meminfo "$W/m" 97957892 $((4 * G))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1000 "$d" --once >>"$f" 2>>"$j"
	printf '0 0 1000 0\n' >"$W/state/state"
	meminfo "$W/m" 97957892 $((40 * G)) $((16 * G)) $((14 * G))
	swaps "$W/s" /swapfile 16777216 2097152
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile NOW_EPOCH=1700 "$d" --once >>"$f" 2>>"$j"
	rm -f "$W/state/state"
	swaps "$W/s"
	meminfo "$W/m" 97957892 $((4 * G))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile SWAPON_BIN="$W/bin/swapon-fails" NOW_EPOCH=2000 "$d" --once >>"$f" 2>>"$j"
	local line
	for line in 'DEPLOY triggered:' 'DEPLOY succeeded.' 'RETRACT triggered:' 'RETRACT succeeded.' 'ERROR: DEPLOY command failed'; do
		grep -qF "$line" "$f" || { echo "  '$line' missing from the log file"; ok=1; }
		grep -qF "$line" "$j" || { echo "  '$line' missing from the journal"; ok=1; }
	done
	grep -qE 'sample:|deploy-check:|retract-check:' "$j" && { echo "  per-cycle lines reached the journal"; ok=1; }
	cp "$f" "$OUT/actions-file.log"
	cp "$j" "$OUT/actions-journal.log"
	return $ok
}

# The unit writes where logrotate rotates, and the folder is Debian's /var/log
# convention (root:adm, 0750 and 0640). No LogNamespace and no sandboxing.
log_wiring() {
	local ok=0
	grep -qx "StandardOutput=append:$LOG_PATH" "$UNIT" || { echo "  the unit does not append to $LOG_PATH"; ok=1; }
	grep -qx 'StandardError=journal' "$UNIT" || { echo "  the unit does not send standard error to the journal"; ok=1; }
	grep -qE '^(LogNamespace|Protect[A-Za-z]*|Private[A-Za-z]*|ReadOnlyPaths|InaccessiblePaths|RootDirectory|ProcSubset)=' "$UNIT" &&
		{ echo "  the unit is sandboxed"; ok=1; }
	[[ -r $LOGROTATE ]] || { echo "  no logrotate file"; return 1; }
	[[ $(sed -n 's/^\(\/[^ {]*\)[[:space:]]*{.*/\1/p' "$LOGROTATE") == "$LOG_PATH" ]] || { echo "  the logrotate file does not name $LOG_PATH"; ok=1; }
	local directive
	for directive in daily 'rotate 7' compress delaycompress missingok notifempty 'maxsize 50M' copytruncate; do
		grep -qx "[[:space:]]*$directive" "$LOGROTATE" || { echo "  logrotate: '$directive' missing"; ok=1; }
	done
	grep -qx 'd /var/log/cushion-swap 0750 root adm -' "$TMPFILES" || { echo "  tmpfiles: the folder line"; ok=1; }
	grep -qx "f $LOG_PATH 0640 root adm -" "$TMPFILES" || { echo "  tmpfiles: the file line"; ok=1; }
	return $ok
}

# The real logrotate, forced three times while the daemon writes about 50
# cycles a second to the file: rotated, compressed after one day's delay,
# the daemon still writing to the same file, and every line accounted for
# except those written inside copytruncate's copy-to-truncate window.
logrotate_while_writing() {
	local d=$1 ok=0 lr=$W/lr cycles lost r
	rm -rf "$lr" "$W/state"
	mkdir -p "$lr"
	[[ -r $LOGROTATE ]] || { echo "  no logrotate file"; return 1; }
	sed "s|^$LOG_PATH |$lr/cushion-swap.log |" "$LOGROTATE" >"$lr/conf"
	grep -q "^$lr/cushion-swap.log {" "$lr/conf" || { echo "  the logrotate file does not name $LOG_PATH"; return 1; }
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon_bg "$lr/cushion-swap.log" "$lr/journal" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile PSI=off \
		PACING=fixed POLL_INTERVAL_SEC=0.02 "$d"
	for r in 1 2 3; do
		sleep 1
		logrotate -f -s "$lr/state" "$lr/conf" 2>>"$lr/logrotate.err" || { echo "  logrotate run $r failed"; ok=1; }
		echo "after rotation $r: $(ls "$lr" | tr '\n' ' ')" >>"$OUT/logrotate-files.txt"
	done
	sleep 1
	stop_bg || ok=1
	[[ -s $lr/cushion-swap.log.1 && -s $lr/cushion-swap.log.2.gz && -s $lr/cushion-swap.log.3.gz ]] ||
		{ echo "  rotated files missing: $(ls "$lr" | tr '\n' ' ')"; ok=1; }
	gzip -t "$lr/cushion-swap.log.2.gz" "$lr/cushion-swap.log.3.gz" 2>/dev/null || { echo "  not gzip"; ok=1; }
	# O_APPEND: after each truncate the daemon writes at the new end, never
	# leaving a hole of NUL bytes where the old file was.
	tr -d '\000' <"$lr/cushion-swap.log" | cmp -s - "$lr/cushion-swap.log" || { echo "  NUL bytes in the log file"; ok=1; }
	{
		zcat "$lr/cushion-swap.log.3.gz" | grep -o 'cycle=[0-9]*' | sed 's/^/3 /'
		zcat "$lr/cushion-swap.log.2.gz" | grep -o 'cycle=[0-9]*' | sed 's/^/2 /'
		grep -o 'cycle=[0-9]*' "$lr/cushion-swap.log.1" | sed 's/^/1 /'
		grep -o 'cycle=[0-9]*' "$lr/cushion-swap.log" | sed 's/^/0 /'
	} | sed 's/cycle=//' >"$lr/cycles"
	# gaps inside one file are failures; gaps between files are the window
	awk '{ if (NR > 1) { if ($2 <= prev) bad = "order"; else if ($2 != prev + 1) { if ($1 == pf) bad = "inside " $1; else lost += $2 - prev - 1 } } prev = $2; pf = $1; n++ }
		END { printf "%d %d %s\n", n, lost + 0, bad }' "$lr/cycles" >"$lr/summary"
	read -r cycles lost r <"$lr/summary"
	echo "cycles written: $cycles; lines lost at the three rotations: $lost (copytruncate's copy-to-truncate window); ${r:-no gap inside a file}" |
		tee "$OUT/logrotate-loss.txt"
	[[ -z $r ]] || ok=1
	((cycles > 100)) || { echo "  too few cycles to measure"; ok=1; }
	# size of one cycle, for the README's numbers
	local bytes
	bytes=$(cat "$lr/cushion-swap.log.1" | wc -c)
	echo "bytes per cycle: $((bytes / $(grep -c 'sample:' "$lr/cushion-swap.log.1")))" >>"$OUT/logrotate-loss.txt"
	ls -l "$lr" >>"$OUT/logrotate-files.txt"
	return $ok
}

# --- Hibernation (Daniel, 2026-10-10: "pointing to the file") --------------

# Generator: the five cases Daniel named, then the size, mismatch and
# switch cases. Daniel's machine: the installer's file names a swap
# partition that is in no fstab line, and the command line has no resume=.
generator_cases() {
	local d=$1 ok=0
	run_gen() {
		rm -rf "$W/gen"
		env CUSHION_SWAP_BIN="$d" KMSG_PATH=/nonexistent CUSHION_SWAP_CONFIG="${CONF:-/nonexistent}" FSTAB_PATH="${GFSTAB:-$W/fstab-area}" \
			CMDLINE_PATH="${CMDLINE:-$W/cmdline-plain}" MEMINFO_PATH="$W/m16" INITRAMFS_RESUME_PATH="${RFILE:-/nonexistent}" \
			DEV_DISK_DIR="$W/disk" SYS_BLOCK_DIR="$W/empty" FINDMNT_BIN="$W/bin/findmnt" FILEFRAG_BIN="$W/bin/filefrag" \
			CGM_PARACHUTE_UNIT="${PUNIT:-/nonexistent}" sh "$GEN" "$W/gen" 2>"$W/gen.log"
		echo "--- ${CASE:-}" >>"$OUT/generator.log"
		cat "$W/gen.log" >>"$OUT/generator.log"
		[[ -e $W/gen/systemd-logind.service.d/50-cushion-swap.conf ]]
	}
	meminfo "$W/m16" 16326000 $((8 * G))
	printf 'RESUME=UUID=swap-part\n' >"$W/resume-part"
	printf 'RESUME=UUID=root-fs\nRESUME_OFFSET=34816\n' >"$W/resume-file"
	printf 'RESUME=none\n' >"$W/resume-none"
	printf 'RESUME=UUID=root-fs\nRESUME_OFFSET=12345\n' >"$W/resume-mismatch"
	echo 'BOOT_IMAGE=/vmlinuz root=UUID=root-fs ro resume=UUID=root-fs resume_offset=34816' >"$W/cmdline-resume"
	echo 'BOOT_IMAGE=/vmlinuz root=UUID=root-fs ro quiet noresume' >"$W/cmdline-noresume"
	CASE=partition-file RFILE=$W/resume-part run_gen &&
		grep -qx 'Environment=SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1' "$W/gen/systemd-logind.service.d/50-cushion-swap.conf" &&
		grep -q "Hibernate offered: $W/resume-part names RESUME=UUID=swap-part, the area $W/dev/vdb3" "$W/gen.log" ||
		{ echo "  the file with a partition UUID (no fstab line, no resume=): Hibernate expected"; ok=1; }
	CASE=swapfile-file RFILE=$W/resume-file run_gen && grep -q "names RESUME=UUID=root-fs offset 34816, the area $W/root/swapfile" "$W/gen.log" ||
		{ echo "  the file with RESUME_OFFSET: Hibernate expected, to the Cushion area"; ok=1; }
	CASE=none RFILE=$W/resume-none run_gen && { echo "  RESUME=none: not offered expected"; ok=1; }
	CASE=none-with-cmdline RFILE=$W/resume-none CMDLINE=$W/cmdline-resume run_gen && { echo "  RESUME=none wins over the command line"; ok=1; }
	CASE=cmdline-only CMDLINE=$W/cmdline-resume run_gen && grep -q 'Hibernate offered: kernel command line names' "$W/gen.log" ||
		{ echo "  no file, resume= on the command line: Hibernate expected"; ok=1; }
	CASE=neither run_gen && { echo "  neither: not offered expected"; ok=1; }
	CASE=noresume RFILE=$W/resume-part CMDLINE=$W/cmdline-noresume run_gen && { echo "  noresume: not offered expected"; ok=1; }
	CASE=mismatch RFILE=$W/resume-mismatch run_gen && { echo "  no swap file at that offset: not offered expected"; ok=1; }
	truncate -s 8G "$W/root/swapfile"
	CASE=smaller-than-ram RFILE=$W/resume-file run_gen && { echo "  area smaller than RAM: not offered expected"; ok=1; }
	truncate -s 16G "$W/root/swapfile"
	printf 'CUSHION_SWAP=off\n' >"$W/conf-off"
	CASE=switched-off CONF=$W/conf-off RFILE=$W/resume-part run_gen && { echo "  switched off: not offered expected"; ok=1; }
	printf 'HIBERNATE="off"\n' >"$W/conf-hib"
	CASE=hibernate-off CONF=$W/conf-hib RFILE=$W/resume-part run_gen && { echo "  HIBERNATE=off: not offered expected"; ok=1; }
	: >"$W/cgm-swap-parachute.service"
	CASE=daniels-parachute PUNIT=$W/cgm-swap-parachute.service RFILE=$W/resume-part run_gen &&
		{ echo "  Daniel's own parachute installed: not offered expected"; ok=1; }
	rm -f "$W/cgm-swap-parachute.service"
	return $ok
}

# Retraction leaves Hibernate offered: with the area off and nothing active,
# the generator (run again at every daemon-reload) still sets the bypass.
offered_after_retract() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	mkdir -p "$W/state"
	printf '0 0 1000 0\n' >"$W/state/state"
	meminfo "$W/m" 16326000 $((10 * G)) $((16 * G)) $((16 * G))
	swaps "$W/s" "$W/root/swapfile" 16777216 0
	FSTAB=$W/fstab-area daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ $(cat "$W/actions" 2>/dev/null) == "swapoff -- $W/root/swapfile" ]] || return 1
	swaps "$W/s"
	rm -rf "$W/gen"
	env CUSHION_SWAP_BIN="$d" CUSHION_SWAP_CONFIG=/nonexistent FSTAB_PATH="$W/fstab-area" CMDLINE_PATH="$W/cmdline-plain" \
		MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" INITRAMFS_RESUME_PATH="$W/resume-file" DEV_DISK_DIR="$W/disk" SYS_BLOCK_DIR="$W/empty" \
		FINDMNT_BIN="$W/bin/findmnt" FILEFRAG_BIN="$W/bin/filefrag" CGM_PARACHUTE_UNIT=/nonexistent sh "$GEN" "$W/gen" 2>/dev/null
	[[ -e $W/gen/systemd-logind.service.d/50-cushion-swap.conf ]]
}

hibernate_env() {
	env "${ENV_COMMON[@]}" FSTAB_PATH="$W/fstab-area" SWAPS_PATH="$W/s" "$@"
}

# Daniel's layout: a swap partition named only in the installer's file.
hibernate_partition_cycle() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	swaps "$W/s"
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-deploy >"$W/log" 2>&1 || return 1
	grep -q "^[0-9]* $W/dev/vdb3 1$" "$W/state/hibernate-deployed" || return 1
	swaps "$W/s" "$W/dev/vdb3" 16777216 0
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-resume >>"$W/log" 2>&1
	[[ $(cat "$W/actions") == "swapon -- $W/dev/vdb3"$'\n'"swapoff -- $W/dev/vdb3" ]] && [[ ! -e $W/state/hibernate-deployed ]]
}

# A swap file: RESUME names its file system, RESUME_OFFSET its first page;
# the other swap file in fstab is not touched.
hibernate_file_cycle() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	printf '%s/root/other-swapfile none swap noauto 0 0\n%s/root/swapfile none swap noauto 0 0\n' "$W" "$W" >"$W/fstab-two"
	swaps "$W/s"
	env "${ENV_COMMON[@]}" FSTAB_PATH="$W/fstab-two" SWAPS_PATH="$W/s" INITRAMFS_RESUME_PATH="$W/resume-file" "$d" --hibernate-deploy >"$W/log" 2>&1 || return 1
	swaps "$W/s" "$W/root/swapfile" 16777216 0
	env "${ENV_COMMON[@]}" FSTAB_PATH="$W/fstab-two" SWAPS_PATH="$W/s" INITRAMFS_RESUME_PATH="$W/resume-file" "$d" --hibernate-resume >>"$W/log" 2>&1
	[[ $(cat "$W/actions") == "swapon -- $W/root/swapfile"$'\n'"swapoff -- $W/root/swapfile" ]]
}

hibernate_keeps_used_area() {
	local d=$1
	rm -f "$W/actions"
	mkdir -p "$W/state"
	printf '100 %s 1\n' "$W/dev/vdb3" >"$W/state/hibernate-deployed"
	swaps "$W/s" "$W/dev/vdb3" 16777216 524288
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-resume >"$W/log" 2>&1
	[[ ! -e $W/actions ]] && grep -q 'retracts it when it is safe' "$W/log"
}

hibernate_already_on() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	swaps "$W/s" "$W/dev/vdb3" 16777216 0
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-deploy >/dev/null 2>&1
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-resume >/dev/null 2>&1
	[[ ! -e $W/actions ]]
}

hibernate_nothing_configured() {
	local d=$1
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	swaps "$W/s"
	hibernate_env "$d" --hibernate-deploy >"$W/log" 2>&1 && [[ ! -e $W/actions ]] && grep -q 'nothing to switch on' "$W/log"
}

# The kernel's resume device (set by the initramfs at boot) must be the one
# the file names; otherwise systemd-sleep refuses, and the log says why.
hibernate_kernel_mismatch() {
	local d=$1 ok=0
	rm -f "$W/actions" "$W/state/hibernate-deployed"
	swaps "$W/s"
	echo 8:1 >"$W/sys/power/resume"
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-deploy >"$W/log" 2>&1
	grep -q 'ERROR: hibernation: the kernel resumes from 8:1' "$W/log" || ok=1
	echo 0:0 >"$W/sys/power/resume"
	rm -f "$W/state/hibernate-deployed"
	return $ok
}

# The initramfs hook carries RESUME_OFFSET into the image as the snippet
# init sources before it reads the command line; read back the way init
# reads it (". conf/conf.d/*", then the command line's resume_offset=).
init_offset() {
	local dest=$1 cmdline=$2 conf x
	(
		export resume_offset=
		for conf in "$dest"/conf/conf.d/*; do
			# shellcheck disable=SC1090
			[ -f "$conf" ] && . "$conf"
		done
		for x in $cmdline; do
			case $x in resume_offset=*) resume_offset=${x#resume_offset=} ;; esac
		done
		echo "${resume_offset:-}"
	)
}

initramfs_hook() {
	local ok=0 it=$W/it got
	rm -rf "$it"
	mkdir -p "$it/etc/conf.d" "$it/dest/conf/conf.d"
	cp "$W/resume-file" "$it/etc/conf.d/resume"
	cp "$W/resume-file" "$it/dest/conf/conf.d/resume"
	CONFDIR=$it/etc DESTDIR=$it/dest RESUME=UUID=root-fs sh "$HOOK" || ok=1
	got=$(init_offset "$it/dest" 'root=UUID=root-fs ro quiet')
	[[ $got == 34816 ]] || { echo "  init's resume_offset from the file alone: '$got', expected 34816"; ok=1; }
	got=$(init_offset "$it/dest" 'root=UUID=root-fs ro resume_offset=777')
	[[ $got == 777 ]] || { echo "  the command line's resume_offset must win: '$got'"; ok=1; }
	rm -f "$it/dest/conf/conf.d/zz-cushion-swap-resume-offset"
	printf 'RESUME=none\nRESUME_OFFSET=34816\n' >"$it/etc/conf.d/resume"
	CONFDIR=$it/etc DESTDIR=$it/dest RESUME=none sh "$HOOK"
	[[ ! -e $it/dest/conf/conf.d/zz-cushion-swap-resume-offset ]] || { echo "  RESUME=none: no offset expected"; ok=1; }
	printf 'RESUME=UUID=swap-part\n' >"$it/etc/conf.d/resume"
	CONFDIR=$it/etc DESTDIR=$it/dest RESUME=UUID=swap-part sh "$HOOK"
	[[ ! -e $it/dest/conf/conf.d/zz-cushion-swap-resume-offset ]] || { echo "  a partition: no offset expected"; ok=1; }
	[[ $(sh "$HOOK" prereqs) == "" ]] || ok=1
	return $ok
}

# --- Pacing ---------------------------------------------------------------

# The loop in compatibility mode: the normal rate, the fast rate while a game
# opens (the launcher's signal or a new launcher process), back on steady
# memory. Both pacings: headroom (the default) caps at the game rate too.
compat_game_opening() {
	local d=$1 pacing=$2 log=$W/compat-$2.log n0 n1 n2 n3 n4 ok=0 i
	rm -rf "$W/state" "$W/run" "$W/proc"
	mkdir -p "$W/run/1000" "$W/proc/100" "$W/proc/101" "$W/proc/sys/kernel"
	echo bash >"$W/proc/100/comm"
	echo kwin_wayland >"$W/proc/101/comm"
	echo 101 >"$W/proc/sys/kernel/ns_last_pid"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	: >"$log"
	local pacing_env=()
	[[ $pacing == default ]] || pacing_env=(PACING="$pacing")
	daemon_bg "$log" "$log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile PSI=off "${pacing_env[@]}" \
		POLL_INTERVAL_SEC=0.4 FAST_INTERVAL_SEC=0.05 STEADY_SEC=1 GAME_OPENING_MAX_SEC=4 \
		RUN_USER_DIR="$W/run" PROC_DIR="$W/proc" "$d"
	sleep 2
	n0=$(samples "$log")
	sleep 1
	n1=$(samples "$log")
	: >"$W/run/1000/cushion-swap-game-opening"
	sleep 0.9
	n2=$(samples "$log")
	grep -q 'game opening (signal from' "$log" || { echo "  no signal start"; ok=1; }
	sleep 2.5
	grep -q 'game loaded (memory steady for 1s)' "$log" || { echo "  fast rate did not stop on steady memory"; ok=1; }
	sleep 0.6
	n3=$(samples "$log")
	sleep 1.2
	n4=$(samples "$log")
	# a new launcher process
	mkdir -p "$W/proc/150" "$W/proc/200"
	echo bash >"$W/proc/150/comm"
	echo reaper >"$W/proc/200/comm"
	echo 200 >"$W/proc/sys/kernel/ns_last_pid"
	sleep 1
	grep -q 'game opening (launcher process started)' "$log" || { echo "  no launcher start"; ok=1; }
	# memory still moving keeps the fast rate until the cap
	for i in $(seq 1 20); do
		meminfo "$W/m" 97957892 $(((40 - i) * G))
		sleep 0.2
	done
	grep -q "game opening longer than 4s" "$log" || { echo "  no cap on a moving opening"; ok=1; }
	stop_bg || { echo "  daemon did not stop"; ok=1; }
	grep -q "pacing=$([[ $pacing == default ]] && echo headroom || echo "$pacing")" "$log" || { echo "  wrong pacing"; ok=1; }
	echo "$pacing: normal 1s: $((n1 - n0)) samples; first 0.9s of opening: $((n2 - n1)); after steady, 1.2s: $((n4 - n3))" | tee -a "$OUT/compat-rates.txt"
	(((n1 - n0) <= 4)) || { echo "  normal rate too fast"; ok=1; }
	(((n2 - n1) >= 6)) || { echo "  fast rate did not start"; ok=1; }
	(((n4 - n3) <= 5)) || { echo "  fast rate stuck after steady memory"; ok=1; }
	cp "$log" "$OUT/compat-loop-$pacing.log"
	return $ok
}

# Headroom pacing, the default (no PACING set): the closer to the
# early-warning floor, the sooner the next sample.
headroom_pacing() {
	local d=$1 log=$W/headroom.log n0 n1 n2 n3 n4 n5 ok=0
	rm -rf "$W/state"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	: >"$log"
	daemon_bg "$log" "$log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile PSI=off \
		POLL_INTERVAL_SEC=0.8 MIN_INTERVAL_SEC=0.05 MAX_ALLOC_MIB_S=1024 RUN_USER_DIR="$W/empty" PROC_DIR="$W/empty" "$d"
	sleep 1
	n0=$(samples "$log")
	sleep 2.4
	n1=$(samples "$log")
	# 50 MiB above the 12 GiB floor at 1 GiB/s: the minimum interval
	meminfo "$W/m" 97957892 $((12 * G + 50 * 1024))
	sleep 0.9
	n2=$(samples "$log")
	sleep 1
	n3=$(samples "$log")
	meminfo "$W/m" 97957892 $((40 * G))
	sleep 1
	n4=$(samples "$log")
	sleep 2.4
	n5=$(samples "$log")
	stop_bg || ok=1
	echo "far from the floor 2.4s: $((n1 - n0)) samples; near it 1s: $((n3 - n2)); far again 2.4s: $((n5 - n4))" | tee "$OUT/headroom-rates.txt"
	grep -q 'pacing=headroom' "$log" || { echo "  headroom is not the default"; ok=1; }
	(((n1 - n0) <= 4)) || { echo "  sampled too often far from the floor"; ok=1; }
	(((n3 - n2) >= 8)) || { echo "  did not speed up near the floor"; ok=1; }
	(((n5 - n4) <= 4)) || { echo "  stayed fast after memory came back"; ok=1; }
	return $ok
}

psi_fallback() {
	local d=$1 log=$W/fallback.log
	rm -rf "$W/state"
	: >"$log"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon_bg "$log" "$log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA=/swapfile PSI_PATH=/nonexistent/pressure "$d"
	sleep 1.5
	stop_bg || return 1
	grep -q 'PSI not available here: compatibility mode' "$log" && grep -q '^MODE=compatibility' "$W/state/status"
}

# sparky-stereo-game-performance tells the daemon a game is opening, and
# still runs the game unchanged (no power-profiles-daemon in the container).
game_performance_signal() {
	local gp=$PKG/../sparky-stereo-game-performance/bin/game-performance out
	mkdir -p "$W/xdg"
	out=$(XDG_RUNTIME_DIR="$W/xdg" PATH=/usr/bin:/bin bash "$gp" echo game-ran 2>/dev/null)
	[[ $out == game-ran && -e $W/xdg/cushion-swap-game-opening ]]
}

psi_helper_refuses() {
	# A trigger the kernel refuses (no such resource) must not count as PSI.
	"$W/psi-wake" /nonexistent "some 150000 1000000" >/dev/null 2>&1
	[[ $? == 2 ]]
}

daniel_harness() {
	# his 12 scenarios and 39 assertions
	DAEMON=$1 bash "$HERE/test_swap_parachute.sh" >"$OUT/daniel-harness.txt" 2>&1
}

suite() {
	local d=$1
	check thresholds-4-8-16-32-64-96GB threshold_cases "$d"
	check reference-96GB-is-Daniels reference_unchanged "$d"
	check settings-file-wins settings_win "$d"
	check deploy-at-floor-own-area-only deploy_own_area_only "$d"
	check deploy-on-rate deploy_on_rate "$d"
	check no-deploy-above-floor no_deploy_above_floor "$d"
	check retract-own-area-only retract_own_area_only "$d"
	check no-retract-under-pressure no_retract_under_pressure "$d"
	check no-retract-without-margin no_retract_without_margin "$d"
	check retract-unused-area retract_unused_area "$d"
	check no-retract-unused-area-before-quiet no_retract_unused_area_before_quiet "$d"
	check no-retract-while-hibernating no_retract_while_hibernating "$d"
	check fstab-noauto-area-only fstab_noauto_only "$d"
	check no-area-no-action no_area_no_action "$d"
	check switched-off switched_off "$d"
	check every-cycle-by-default every_cycle_by_default "$d"
	check actions-in-file-and-journal actions_in_both "$d"
	check log-wiring log_wiring
	check logrotate-while-writing logrotate_while_writing "$d"
	check generator-resume-sources generator_cases "$d"
	check hibernate-offered-after-retract offered_after_retract "$d"
	check hibernate-partition-not-in-fstab hibernate_partition_cycle "$d"
	check hibernate-swap-file-from-offset hibernate_file_cycle "$d"
	check hibernate-keeps-used-area hibernate_keeps_used_area "$d"
	check hibernate-area-already-on hibernate_already_on "$d"
	check hibernate-nothing-configured hibernate_nothing_configured "$d"
	check hibernate-kernel-mismatch-logged hibernate_kernel_mismatch "$d"
	check initramfs-hook-offset initramfs_hook
	check compat-game-opening-headroom compat_game_opening "$d" default
	check compat-game-opening-fixed compat_game_opening "$d" fixed
	check headroom-pacing-default headroom_pacing "$d"
	check psi-fallback psi_fallback "$d"
	check daniel-harness-39 daniel_harness "$d"
}

# Planted faults: each must fail exactly where named. The fault goes into a
# copy of one file: the daemon (default), the generator, the hook, the unit,
# the logrotate file (a sed, or "absent").
mutant() {
	local name=$1 expect=$2 sed_expr=$3 target=${4:-daemon} source m=$W/mutant-$1
	case $target in
	daemon) source=$PKG/sbin/cushion-swap ;;
	generator) source=$GEN ;;
	hook) source=$HOOK ;;
	unit) source=$UNIT ;;
	logrotate) source=$LOGROTATE ;;
	esac
	if [[ $sed_expr == absent ]]; then
		m=/nonexistent
	else
		sed "$sed_expr" "$source" >"$m"
		chmod +x "$m"
		if cmp -s "$m" "$source"; then
			echo "FAIL mutant-$name (the fault was not planted)"
			FAIL=$((FAIL + 1))
			return
		fi
	fi
	local result d=$PKG/sbin/cushion-swap
	mkdir -p "$OUT/mutant-$name"
	case $target in
	daemon) d=$m ;;
	generator) local GEN=$m ;;
	hook) local HOOK=$m ;;
	unit) local UNIT=$m ;;
	logrotate) local LOGROTATE=$m ;;
	esac
	result=$(OUT=$OUT/mutant-$name PASS=0 FAIL=0 suite "$d" 2>&1)
	echo "$result" >"$OUT/mutant-$name.txt"
	local expected
	for expected in $expect; do
		if ! grep -qx "FAIL $expected" <<<"$result"; then
			echo "FAIL mutant-$name (expected FAIL $expected)"
			FAIL=$((FAIL + 1))
			return
		fi
	done
	echo "PASS mutant-$name: $(grep -c '^FAIL' <<<"$result") checks fail, including $expect"
	PASS=$((PASS + 1))
}

make_fakes
set_env
check psi-helper-builds build_helper
[[ -x $W/psi-wake ]] || exit 1
check psi-helper-refuses-without-psi psi_helper_refuses
check game-performance-signal game_performance_signal
suite "$PKG/sbin/cushion-swap"
[[ ${QUICK:-} == 1 ]] && { echo "SUMMARY: $PASS passed, $FAIL failed (no planted faults)"; ((FAIL == 0)); exit; }
# Daniel's rules (0.1.0)
mutant late-deploy "deploy-at-floor-own-area-only" 's/((MEM_AVAILABLE_KIB < DEPLOY_HARD_KIB)) \&\& hard_trigger=1/((MEM_AVAILABLE_KIB < DEPLOY_HARD_KIB \/ 2)) \&\& hard_trigger=1/'
mutant no-rate-trigger "deploy-on-rate" 's/^\t\t\t\t\trate_trigger=1$/\t\t\t\t\trate_trigger=0/'
mutant retract-under-pressure "no-retract-under-pressure no-retract-unused-area-before-quiet" 's/ \&\& quiet_elapsed >= QUIET_SECONDS \&\& !hold))/ \&\& !hold))/'
mutant retract-without-margin "no-retract-without-margin" 's/ \&\& MEM_AVAILABLE_KIB > margin_kib) || area_empty)/) || area_empty)/'
mutant every-swap-area "deploy-at-floor-own-area-only retract-own-area-only" 's/"\$SWAPON_BIN" -- "\$AREA"/"$SWAPON_BIN" -a/; s/"\$SWAPOFF_BIN" -- "\$AREA"/"$SWAPOFF_BIN" -a/'
mutant stuck-fast-rate "compat-game-opening-headroom compat-game-opening-fixed" 's/^\t\tFAST_SINCE_MS=0$/\t\t:/'
# 1. pacing
mutant pacing-default-fixed "headroom-pacing-default compat-game-opening-headroom" 's/^PACING=\${PACING:-headroom}$/PACING=${PACING:-fixed}/'
mutant headroom-ignored "headroom-pacing-default" 's/^\t((ms < MIN_MS)) \&\& ms=\$MIN_MS$/\tms=$max_ms/'
mutant headroom-ignores-game "compat-game-opening-headroom" 's/^\t((FAST_SINCE_MS)) \&\& cap_ms=\$FAST_MS$/\t:/'
# 3. an unused area, and Hibernate kept
mutant unused-area-kept "retract-unused-area hibernate-offered-after-retract" 's/ || area_empty) \&\& quiet_elapsed/) \&\& quiet_elapsed/'
mutant retract-during-hibernation "no-retract-while-hibernating" 's/ \&\& !hold))/))/'
mutant offered-only-while-on "hibernate-offered-after-retract" 's|^target=\$(value TARGET)$|target=$(value TARGET); grep -q "^$target[[:space:]]" "${SWAPS_PATH:-/proc/swaps}" \|\| exit 0|' generator
mutant skip-switch-on "hibernate-partition-not-in-fstab hibernate-swap-file-from-offset" 's/^\t\tif ! "\$SWAPON_BIN" -- "\$TARGET"; then$/\t\tif false; then/'
# 4. logging
mutant actions-not-in-journal "actions-in-file-and-journal every-cycle-by-default" 's/^\t((JOURNAL_TOO)) \&\& printf .%s\\n. "\$line" >\&2$/\t:/'
mutant decisions-only-default "every-cycle-by-default" 's/^LOG_EVERY_CYCLE=\${LOG_EVERY_CYCLE:-yes}$/LOG_EVERY_CYCLE=${LOG_EVERY_CYCLE:-no}/'
mutant logrotate-absent "log-wiring logrotate-while-writing" absent logrotate
mutant logrotate-other-path "log-wiring logrotate-while-writing" 's|^/var/log/cushion-swap/cushion-swap.log {|/var/log/cushion-swap.log {|' logrotate
mutant unit-log-elsewhere "log-wiring" 's|^StandardOutput=append:.*|StandardOutput=journal|' unit
mutant unit-log-namespace "log-wiring" 's|^StandardError=journal$|StandardError=journal\nLogNamespace=cushion-swap|' unit
# 5. Hibernate from the installer's file
mutant ignore-the-file "generator-resume-sources hibernate-partition-not-in-fstab" 's/^\tif \[\[ -r \$INITRAMFS_RESUME_PATH \]\]; then$/\tif false; then/'
mutant hook-drops-offset "initramfs-hook-offset" 's/^echo "resume_offset=\$offset"/: "resume_offset=$offset"/' hook
echo "SUMMARY: $PASS passed, $FAIL failed"
echo "SUMMARY: $PASS passed, $FAIL failed" >"$OUT/summary.txt"
((FAIL == 0))
