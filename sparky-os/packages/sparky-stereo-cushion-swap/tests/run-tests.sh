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
command -v logrotate >/dev/null 2>&1 || { echo 'ERROR: tests require logrotate; install logrotate in the test container' >&2; exit 2; }
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
UNIT=${UNIT_UNDER_TEST:-$PKG/lib/systemd/system/cushion-swap.service}
POSTINST=${POSTINST_UNDER_TEST:-}
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
	printf '#!/bin/sh\necho "swapon: $2: swapon failed: Invalid argument" >&2\nexit 255\n' >"$W/bin/swapon-says"
	printf '#!/bin/sh\necho "swapoff: $2: swapoff failed: Cannot allocate memory" >&2\nexit 255\n' >"$W/bin/swapoff-says"
	# the allocation-rate helper: its fingerprint, and a measurement (short runs never reach one)
	printf '#!/bin/sh\nif [ "$1" = --fingerprint ]; then echo test-fingerprint; else echo "1024 1 1 0.010"; fi\n' >"$W/bin/alloc-rate"
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
	ENV_COMMON=(LOG_EVERY_CYCLE=yes CALIBRATION_DIR="$W/calibration" CUSHION_SWAP_CONFIG=/nonexistent STATE_DIR="$W/state" SWAPON_BIN="$W/bin/swapon" SWAPOFF_BIN="$W/bin/swapoff"
		ALLOC_RATE_HELPER="$W/bin/alloc-rate" CUSHION_SWAP_LANG_DIR="$PKG/lang" LANG=C.UTF-8
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
	[[ $? == 0 && ! -e $W/actions ]] && grep -qx 'STATE=disabled' "$W/state/status"
}

# --- Logging (Daniel, 2026-10-10) -----------------------------------------
# The unit appends standard output to the log file and sends standard error
# to the journal; here two files stand for them.

problems_only_default() {
	local d=$1 ok=0
	rm -rf "$W/state" "$W/quiet"
	mkdir -p "$W/quiet"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon_bg "$W/quiet/file" "$W/quiet/journal" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" \
		CUSHION_SWAP_AREA="$W/root/swapfile" PSI=off PACING=fixed POLL_INTERVAL_SEC=0.1 LOG_EVERY_CYCLE= "$d"
	sleep 0.6
	stop_bg || ok=1
	[[ ! -s $W/quiet/file && ! -s $W/quiet/journal ]] || { echo '  routine output with problem-only default'; ok=1; }
	return $ok
}

every_cycle_opt_in() {
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
	grep -qE 'cushion-swap: starting|thresholds \(' "$W/lg/journal" &&
		{ echo "  routine startup chatter reached the journal"; ok=1; }
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
	for directive in weekly 'rotate 1' compress delaycompress missingok notifempty copytruncate; do
		grep -qx "[[:space:]]*$directive" "$LOGROTATE" || { echo "  logrotate: '$directive' missing"; ok=1; }
	done
	grep -qE '^[[:space:]]*(daily|hourly|maxsize|size|minsize)([[:space:]]|$)' "$LOGROTATE" && { echo '  rotation sooner than weekly'; ok=1; }
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
		cp "$lr/cushion-swap.log.1" "$lr/record-$r"
		echo "after rotation $r: $(ls "$lr" | tr '\n' ' ')" >>"$OUT/logrotate-files.txt"
	done
	sleep 1
	stop_bg || ok=1
	[[ -s $lr/cushion-swap.log.1 && ! -e $lr/cushion-swap.log.2 ]] ||
		{ echo "  expected exactly one previous week's file"; ok=1; }
	# delaycompress with rotate 1 leaves the only archive uncompressed.
	cp "$lr/cushion-swap.log.1" "$lr/before-no-force"
	logrotate -s "$lr/state" "$lr/conf" 2>>"$lr/logrotate.err" || ok=1
	cmp -s "$lr/before-no-force" "$lr/cushion-swap.log.1" ||
		{ echo '  rotation repeated before the weekly deadline'; ok=1; }
	# O_APPEND: after each truncate the daemon writes at the new end, never
	# leaving a hole of NUL bytes where the old file was.
	tr -d '\000' <"$lr/cushion-swap.log" | cmp -s - "$lr/cushion-swap.log" || { echo "  NUL bytes in the log file"; ok=1; }
	{
		cat "$lr/record-1" | grep -o 'cycle=[0-9]*' | sed 's/^/3 /'
		cat "$lr/record-2" | grep -o 'cycle=[0-9]*' | sed 's/^/2 /'
		grep -o 'cycle=[0-9]*' "$lr/record-3" | sed 's/^/1 /'
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

calibration_cache() {
	local d=$1 ok=0 cache=$W/calib-test
	rm -rf "$W/state" "$cache"
	mkdir -p "$cache/proc"
	printf '#!/bin/bash\nif [[ ${1:-} == --fingerprint ]]; then cat "%s/id"; else echo measured >>"%s/calls"; echo "512 1 1 0.020"; fi\n' "$cache" "$cache" >"$cache/helper"
	chmod +x "$cache/helper"
	printf '#!/bin/sh\nprintf "ready\\n"\nexec sleep 60\n' >"$cache/psi-helper"
	chmod +x "$cache/psi-helper"
	echo kernel-a >"$cache/id"
	echo 'cpu 100 0 0 100 0 0 0 0' >"$cache/stat"
	meminfo "$W/m" 4194304 $((3 * G))
	swaps "$W/s"
	# a kernel with PSI (the file exists; empty, so it reports no stall) and a helper that arms it: PSI mode
	: >"$cache/pressure"
	daemon_bg "$cache/log" "$cache/log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" PSI=auto PSI_PATH="$cache/pressure" PSI_WAKE="$cache/psi-helper" SAFETY_TICK_SEC=0.05 \
		PACING=fixed POLL_INTERVAL_SEC=0.05 RUN_USER_DIR="$W/empty" PROC_DIR="$cache/proc" \
		CPU_STAT_PATH="$cache/stat" CALIBRATION_CHECK_SEC=0.1 CALIBRATION_DIR="$cache/state" ALLOC_RATE_HELPER="$cache/helper" "$d"
	sleep 0.2
	echo 'cpu 500 0 0 100 0 0 0 0' >"$cache/stat"
	sleep 0.2
	[[ ! -e $cache/calls ]] || { echo '  measured on a busy CPU'; ok=1; }
	mkdir -p "$cache/proc/1"
	echo powerprofilesct >"$cache/proc/1/comm"
	echo 'cpu 500 0 0 1000 0 0 0 0' >"$cache/stat"
	sleep 0.2
	[[ ! -e $cache/calls ]] || { echo '  measured while the game profile wrapper was running'; ok=1; }
	rm -rf "$cache/proc/1"
	echo 'cpu 500 0 0 2000 0 0 0 0' >"$cache/stat"
	sleep 0.3
	stop_bg || ok=1
	[[ $(cat "$cache/state/allocation-rate" 2>/dev/null) == 'kernel-a 1024 512 1 1 0.020' ]] || { echo '  missing rate or safety factor'; ok=1; }
	[[ $(wc -l <"$cache/calls" 2>/dev/null) == 1 ]] || ok=1
	for id in kernel-a kernel-b; do
		echo "$id" >"$cache/id"
		echo 'cpu 500 0 0 1000 0 0 0 0' >"$cache/stat"
		daemon_bg "$cache/log" "$cache/log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" PSI=off PSI_PATH=/nonexistent \
			PACING=fixed POLL_INTERVAL_SEC=0.05 RUN_USER_DIR="$W/empty" PROC_DIR="$W/empty" \
			CPU_STAT_PATH="$cache/stat" CALIBRATION_CHECK_SEC=0.1 CALIBRATION_DIR="$cache/state" ALLOC_RATE_HELPER="$cache/helper" "$d"
		sleep 0.2
		echo 'cpu 500 0 0 2000 0 0 0 0' >"$cache/stat"
		sleep 0.3
		stop_bg || ok=1
		local expected=1
		[[ $id == kernel-b ]] && expected=2
		[[ $(wc -l <"$cache/calls") == "$expected" ]] || { echo "  wrong cache invalidation for $id"; ok=1; }
	done
	grep -qx 'MAX_ALLOC_MIB_S=1024' "$W/state/status" || ok=1
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

# --- Nothing fails silently (ORDER 346b: U17, U18 and U54 of ORDER 343's audit) --------
# Daniel, 2026-11-01: "either it works or not and the user must know". Whatever keeps the
# daemon from protecting memory is kept in $STATE_DIR/problems, named in the status and said
# once; --status exits 0 only while memory is protected.

AREA_OK=$W/root/swapfile

status_value() {
	sed -n "s/^$1=//p" "$W/state/status" 2>/dev/null
}

kept_problem() {
	[[ -f $W/state/problems/$1 ]] && grep -q -- "$2" "$W/state/problems/$1"
}

# The control: a healthy cycle protects memory, keeps no problem, and --status says so with 0.
protecting_control() {
	local d=$1 ok=0
	rm -rf "$W/state" "$W/actions"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" "$d" --once >"$W/log" 2>&1
	[[ $(status_value PROTECTION) == yes ]] || { echo "  PROTECTION=$(status_value PROTECTION)"; ok=1; }
	[[ -z $(status_value PROBLEMS) ]] || { echo "  PROBLEMS=$(status_value PROBLEMS)"; ok=1; }
	daemon "$d" --status >/dev/null
	[[ $? == 0 ]] || { echo "  --status did not exit 0"; ok=1; }
	return $ok
}

# U18: unreadable or broken /proc/meminfo: Daniel's fail-safe (no action) stays, and memory is
# said to be unprotected until the numbers come back.
meminfo_unreadable() {
	local d=$1 ok=0 rc
	rm -rf "$W/state" "$W/actions"
	swaps "$W/s"
	daemon MEMINFO_PATH="$W/nonexistent-meminfo" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/actions ]] || { echo "  acted without the numbers"; ok=1; }
	[[ $(status_value PROTECTION) == no ]] || { echo "  PROTECTION=$(status_value PROTECTION)"; ok=1; }
	kept_problem meminfo 'it is missing or unreadable' || { echo "  no meminfo problem kept"; ok=1; }
	daemon "$d" --status >/dev/null
	rc=$?
	[[ $rc == 2 ]] || { echo "  --status exited $rc, not 2"; ok=1; }
	meminfo "$W/m" 97957892 $((40 * G))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" LOG_EVERY_CYCLE= "$d" --once >"$W/log" 2>&1
	[[ ! -e $W/state/problems/meminfo && $(status_value PROTECTION) == yes ]] || { echo "  not cleared when readable again"; ok=1; }
	# Daniel's problems-only default log: that the problem is gone is no log line
	[[ ! -s $W/log ]] || { echo "  the default log has more than problems: $(head -1 "$W/log")"; ok=1; }
	return $ok
}

swaps_unreadable() {
	local d=$1
	rm -rf "$W/state"
	meminfo "$W/m" 97957892 $((40 * G))
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/nonexistent-swaps" CUSHION_SWAP_AREA="$AREA_OK" "$d" --once >"$W/log" 2>&1
	[[ $(status_value PROTECTION) == no ]] && kept_problem swaps "$W/nonexistent-swaps"
}

# U18: no area, or an area that is not there: the service runs, memory is not protected.
no_area_unprotected() {
	local d=$1 ok=0 rc
	rm -rf "$W/state"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" "$d" --once >"$W/log" 2>&1
	[[ $(status_value PROTECTION) == no ]] && kept_problem no-area 'no swap area is configured' || { echo "  no area: $(status_value PROTECTION)"; ok=1; }
	daemon "$d" --status >/dev/null
	rc=$?
	[[ $rc == 2 ]] || { echo "  no area: --status exited $rc"; ok=1; }
	rm -rf "$W/state"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$W/no/such/area" "$d" --once >"$W/log" 2>&1
	[[ $(status_value PROTECTION) == no ]] && kept_problem area-missing "$W/no/such/area" || { echo "  missing area: $(status_value PROTECTION)"; ok=1; }
	return $ok
}

# U18: swapon fails at the floor: kept with swapon's own error, said once, cleared by a success.
deploy_failure_kept() {
	local d=$1 ok=0 n
	rm -rf "$W/state" "$W/actions"
	meminfo "$W/m" 97957892 $((4 * G))
	swaps "$W/s"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" SWAPON_BIN="$W/bin/swapon-says" NOW_EPOCH=1000 "$d" --once >"$W/log" 2>"$W/journal"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" SWAPON_BIN="$W/bin/swapon-says" NOW_EPOCH=1003 "$d" --once >>"$W/log" 2>>"$W/journal"
	[[ $(status_value PROTECTION) == no ]] || { echo "  PROTECTION=$(status_value PROTECTION)"; ok=1; }
	kept_problem deploy-failed 'swapon failed: Invalid argument' || { echo "  swapon's error not kept"; ok=1; }
	n=$(grep -c 'could not switch its swap area on' "$W/journal")
	((n == 1)) || { echo "  said $n times in the journal, not once"; ok=1; }
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" NOW_EPOCH=1006 "$d" --once >>"$W/log" 2>&1
	[[ ! -e $W/state/problems/deploy-failed ]] || { echo "  not cleared after a successful swapon"; ok=1; }
	return $ok
}

retract_failure_kept() {
	local d=$1
	rm -rf "$W/state"
	mkdir -p "$W/state"
	printf '0 0 1000 0\n' >"$W/state/state"
	meminfo "$W/m" 97957892 $((40 * G)) $((16 * G)) $((14 * G))
	swaps "$W/s" "$AREA_OK" 8388608 2097152
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" SWAPOFF_BIN="$W/bin/swapoff-says" NOW_EPOCH=1700 "$d" --once >"$W/log" 2>&1
	[[ $(status_value PROTECTION) == degraded ]] && kept_problem retract-failed 'Cannot allocate memory'
}

# U18: --status never says "stopped" with 0, and never trusts a file it cannot read or a daemon
# that is gone.
status_exit_codes() {
	local d=$1 ok=0 out rc
	rm -rf "$W/state"
	out=$(daemon SYSTEMCTL_BIN=/bin/false "$d" --status)
	rc=$?
	[[ $rc == 3 && $out == *PROTECTION=no* ]] || { echo "  no status file: exit $rc: $out"; ok=1; }
	mkdir -p "$W/state/status"
	out=$(daemon "$d" --status 2>/dev/null)
	rc=$?
	[[ $rc == 4 && $out == *STATE=unknown* ]] || { echo "  unreadable status: exit $rc: $out"; ok=1; }
	rm -rf "$W/state"
	mkdir -p "$W/state"
	printf 'STATE=off\nPROTECTION=yes\nPROBLEMS=\nPID=999999\n' >"$W/state/status"
	out=$(daemon "$d" --status)
	rc=$?
	[[ $rc == 3 && $out == *RUNNING=no* ]] || { echo "  a gone daemon's status: exit $rc"; ok=1; }
	return $ok
}

# U18: the unit says why the daemon stopped (ExecStopPost), and a stop that was not asked for is a
# problem; a stop the person asked for is not one.
stopped_says_why() {
	local d=$1 ok=0
	rm -rf "$W/state"
	mkdir -p "$W/state"
	printf 'STATE=off\nPROTECTION=yes\n' >"$W/state/status"
	daemon SERVICE_RESULT=exit-code EXIT_CODE=exited EXIT_STATUS=1 "$d" --stopped >"$W/log" 2>&1
	[[ $(status_value STATE) == stopped && $(status_value PROTECTION) == no ]] || { echo "  failure: STATE=$(status_value STATE)"; ok=1; }
	kept_problem service-failed 'result exit-code, exited 1' || { echo "  no service-failed problem"; ok=1; }
	local first
	first=$(sed -n 's/^FIRST=//p' "$W/state/problems/service-failed")
	sleep 1.1
	daemon SERVICE_RESULT=signal EXIT_CODE=killed EXIT_STATUS=KILL "$d" --stopped >>"$W/log" 2>&1
	[[ $(sed -n 's/^FIRST=//p' "$W/state/problems/service-failed") == "$first" ]] || { echo "  a restart loop is not one problem"; ok=1; }
	daemon SERVICE_RESULT=success EXIT_CODE=killed EXIT_STATUS=TERM "$d" --stopped >>"$W/log" 2>&1
	[[ ! -e $W/state/problems/service-failed && $(status_value STATE) == stopped ]] || { echo "  a requested stop kept a problem"; ok=1; }
	printf 'STATE=disabled\nPROTECTION=no\n' >"$W/state/status"
	daemon SERVICE_RESULT=success EXIT_CODE=exited EXIT_STATUS=0 "$d" --stopped >>"$W/log" 2>&1
	[[ $(status_value STATE) == disabled ]] || { echo "  CUSHION_SWAP=off lost its state"; ok=1; }
	return $ok
}

# U18: a kernel with PSI whose helper is missing, whose trigger is refused or lost: the poller
# protects memory, and the person is told. A kernel without PSI, or PSI=off, is no problem.
psi_failures_said() {
	local d=$1 ok=0 log=$W/psilost.log
	: >"$W/pressure"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	# missing helper
	rm -rf "$W/state"
	daemon_bg "$log" "$log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI_PATH="$W/pressure" \
		PSI_WAKE="$W/no-psi-wake" PACING=fixed POLL_INTERVAL_SEC=0.1 RUN_USER_DIR="$W/empty" PROC_DIR="$W/empty" "$d"
	sleep 0.6
	stop_bg || ok=1
	[[ $(status_value MODE) == compatibility && $(status_value PROTECTION) == degraded ]] && kept_problem psi-missing no-psi-wake ||
		{ echo "  missing helper: MODE=$(status_value MODE) PROTECTION=$(status_value PROTECTION)"; ok=1; }
	# the trigger lost a moment after it was armed
	rm -rf "$W/state"
	printf '#!/bin/sh\necho ready\nsleep 0.2\necho "psi-wake: trigger lost" >&2\nexit 3\n' >"$W/bin/psi-dies"
	chmod +x "$W/bin/psi-dies"
	daemon_bg "$log" "$log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI_PATH="$W/pressure" \
		PSI_WAKE="$W/bin/psi-dies" SAFETY_TICK_SEC=0.1 PACING=fixed POLL_INTERVAL_SEC=0.1 RUN_USER_DIR="$W/empty" PROC_DIR="$W/empty" "$d"
	sleep 1
	stop_bg || ok=1
	[[ $(status_value MODE) == compatibility && $(status_value PROTECTION) == degraded ]] && kept_problem psi-lost 'trigger lost (exit status 3)' ||
		{ echo "  lost trigger: MODE=$(status_value MODE) PROTECTION=$(status_value PROTECTION)"; ok=1; }
	# the controls: no PSI in this kernel, and PSI=off, are modes, not problems
	rm -rf "$W/state"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI_PATH=/nonexistent/pressure "$d" --once >/dev/null 2>&1
	rm -rf "$W/state"
	daemon_bg "$log" "$log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI_PATH=/nonexistent/pressure \
		PACING=fixed POLL_INTERVAL_SEC=0.1 RUN_USER_DIR="$W/empty" PROC_DIR="$W/empty" "$d"
	sleep 0.5
	stop_bg || ok=1
	[[ $(status_value PROTECTION) == yes && $(status_value MODE_REASON) == *'has no PSI'* ]] || { echo "  no PSI here counted as a problem"; ok=1; }
	return $ok
}

# U54: the allocation-rate helper missing, its measurement failing, its result not saved: each kept and
# said; the conservative pace stays, a named choice is offered, and a failed measurement is tried again
# as before, its problem cleared by the success.
calibration_problems() {
	local d=$1 ok=0 c=$W/calib346
	rm -rf "$W/state" "$c"
	mkdir -p "$c/proc"
	meminfo "$W/m" 4194304 $((3 * G))
	swaps "$W/s"
	daemon_bg "$c/log" "$c/log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI=off PSI_PATH=/nonexistent PACING=fixed \
		POLL_INTERVAL_SEC=0.05 RUN_USER_DIR="$W/empty" PROC_DIR="$c/proc" ALLOC_RATE_HELPER="$c/none" "$d"
	sleep 0.4
	daemon PROC_DIR=/proc "$d" --status >/dev/null
	[[ $? == 1 ]] || { echo "  --status does not say a problem is kept"; ok=1; }
	stop_bg || ok=1
	[[ $(status_value CALIBRATION) == unavailable ]] && kept_problem calibration-unavailable 'MAX_ALLOC_MIB_S=8192' ||
		{ echo "  missing helper: CALIBRATION=$(status_value CALIBRATION)"; ok=1; }
	# the measurement fails twice, then works: kept from the first failure, tried again, cleared
	rm -rf "$W/state"
	printf '#!/bin/sh\nif [ "$1" = --fingerprint ]; then echo fp; exit 0; fi\necho try >>%s/calls\nif [ $(wc -l <%s/calls) -le 2 ]; then echo "alloc-rate: mmap: Cannot allocate memory" >&2; exit 1; fi\necho "512 1 1 0.020"\n' "$c" "$c" >"$c/helper"
	chmod +x "$c/helper"
	echo 'cpu 100 0 0 100 0 0 0 0' >"$c/stat"
	daemon_bg "$c/log" "$c/log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI=off PACING=fixed \
		POLL_INTERVAL_SEC=0.05 RUN_USER_DIR="$W/empty" PROC_DIR="$c/proc" CPU_STAT_PATH="$c/stat" CALIBRATION_CHECK_SEC=0.05 \
		PSI_PATH=/nonexistent CALIBRATION_RETRY_SEC=0.05 CALIBRATION_DIR="$c/state" ALLOC_RATE_HELPER="$c/helper" "$d"
	local i seen=0
	for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
		echo "cpu 500 0 0 $((1000 * i)) 0 0 0 0" >"$c/stat"
		sleep 0.15
		[[ $(status_value CALIBRATION) == failed ]] && kept_problem calibration-failed 'Cannot allocate memory' && seen=1
	done
	stop_bg || ok=1
	((seen)) || { echo "  the failed measurement was not kept"; ok=1; }
	[[ $(wc -l <"$c/calls" 2>/dev/null) == 3 ]] || { echo "  $(wc -l <"$c/calls" 2>/dev/null) tries, not 3"; ok=1; }
	[[ $(status_value CALIBRATION) == measured && ! -e $W/state/problems/calibration-failed ]] ||
		{ echo "  not cleared by the success: CALIBRATION=$(status_value CALIBRATION)"; ok=1; }
	# measured, but the cache cannot be written: in use, and said
	rm -rf "$W/state" "$c/calls"
	: >"$c/blocked"
	daemon_bg "$c/log" "$c/log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI=off PACING=fixed \
		POLL_INTERVAL_SEC=0.05 RUN_USER_DIR="$W/empty" PROC_DIR="$c/proc" CPU_STAT_PATH="$c/stat" CALIBRATION_CHECK_SEC=0.05 \
		PSI_PATH=/nonexistent CALIBRATION_DIR="$c/blocked/sub" ALLOC_RATE_HELPER="$W/bin/alloc-rate" "$d"
	for i in 13 14 15 16; do
		echo "cpu 500 0 0 $((1000 * i)) 0 0 0 0" >"$c/stat"
		sleep 0.15
	done
	stop_bg || ok=1
	[[ $(status_value CALIBRATION) == measured && $(status_value MAX_ALLOC_MIB_S) == 2048 ]] && kept_problem calibration-save "$c/blocked/sub" ||
		{ echo "  unsaved measurement: CALIBRATION=$(status_value CALIBRATION) MAX=$(status_value MAX_ALLOC_MIB_S)"; ok=1; }
	return $ok
}

# U18 and the audit's resumed-hibernation note: a failed switch-off after resume, a kernel resume
# device that differs, and a failed switch-on each fail their command and are kept.
hibernate_failures_kept() {
	local d=$1 ok=0 rc
	rm -rf "$W/state" "$W/actions"
	mkdir -p "$W/state"
	printf '100 %s 1\n' "$W/dev/vdb3" >"$W/state/hibernate-deployed"
	swaps "$W/s" "$W/dev/vdb3" 16777216 0
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" SWAPOFF_BIN="$W/bin/swapoff-says" "$d" --hibernate-resume >"$W/log" 2>&1
	rc=$?
	[[ $rc == 1 ]] && kept_problem resume-swapoff 'Cannot allocate memory' || { echo "  resume swapoff: exit $rc"; ok=1; }
	rm -rf "$W/state"
	swaps "$W/s"
	echo 8:1 >"$W/sys/power/resume"
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" "$d" --hibernate-deploy >"$W/log" 2>&1
	rc=$?
	echo 0:0 >"$W/sys/power/resume"
	[[ $rc == 1 ]] && kept_problem hibernate-mismatch 'update-initramfs -u' || { echo "  kernel mismatch: exit $rc"; ok=1; }
	rm -rf "$W/state"
	hibernate_env INITRAMFS_RESUME_PATH="$W/resume-part" SWAPON_BIN="$W/bin/swapon-says" "$d" --hibernate-deploy >"$W/log" 2>&1
	rc=$?
	[[ $rc == 1 ]] && kept_problem hibernate-swapon 'Invalid argument' || { echo "  hibernate swapon: exit $rc"; ok=1; }
	return $ok
}

# U17: the package's readiness check, with systemctl answering as systemd would.
wait_ready_cases() {
	local d=$1 ok=0 rc since out
	mkdir -p "$W/sysctl"
	printf '#!/bin/sh\ncase "$1" in is-enabled) cat %s/sysctl/enabled ;; is-active|--quiet) exit 3 ;; show) echo ActiveState=failed; echo SubState=failed; echo Result=exit-code; echo UnitFileState=enabled ;; esac\n' "$W" >"$W/bin/systemctl"
	chmod +x "$W/bin/systemctl"
	echo enabled >"$W/sysctl/enabled"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	# a daemon started after the restart, protecting: silent, 0
	rm -rf "$W/state"
	since=$(date +%s)
	daemon_bg "$W/wr.log" "$W/wr.log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" CUSHION_SWAP_AREA="$AREA_OK" PSI=off PACING=fixed POLL_INTERVAL_SEC=0.1 \
		RUN_USER_DIR="$W/empty" PROC_DIR=/proc "$d"
	out=$(daemon SYSTEMCTL_BIN="$W/bin/systemctl" PROC_DIR=/proc READY_WAIT_SEC=3 "$d" --wait-ready "$since" 2>&1)
	rc=$?
	stop_bg || ok=1
	[[ $rc == 0 && -z $out ]] || { echo "  ready daemon: exit $rc: $out"; ok=1; }
	# a daemon that never started after the restart: said with systemd's view, exit 1
	out=$(daemon SYSTEMCTL_BIN="$W/bin/systemctl" PROC_DIR=/proc READY_WAIT_SEC=1 "$d" --wait-ready "$((since + 100))" 2>&1)
	rc=$?
	[[ $rc == 1 && $out == *'protection could not start'*'Result=exit-code'* ]] || { echo "  no daemon: exit $rc: $out"; ok=1; }
	# started, but no area: running is not protecting
	rm -rf "$W/state"
	since=$(date +%s)
	daemon_bg "$W/wr.log" "$W/wr.log" MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" PSI=off PACING=fixed POLL_INTERVAL_SEC=0.1 \
		RUN_USER_DIR="$W/empty" PROC_DIR=/proc "$d"
	out=$(daemon SYSTEMCTL_BIN="$W/bin/systemctl" PROC_DIR=/proc READY_WAIT_SEC=3 "$d" --wait-ready "$since" 2>&1)
	rc=$?
	stop_bg || ok=1
	[[ $rc == 0 && $out == *'NOT fully protected'*'no swap area is configured'* ]] || { echo "  no area: exit $rc: $out"; ok=1; }
	# the person's own switches are said as their choice
	echo disabled >"$W/sysctl/enabled"
	out=$(daemon SYSTEMCTL_BIN="$W/bin/systemctl" READY_WAIT_SEC=1 "$d" --wait-ready "$since" 2>&1)
	rc=$?
	[[ $rc == 0 && $out == *'switched off by your choice (cushion-swap.service is disabled)'* ]] || { echo "  disabled: exit $rc: $out"; ok=1; }
	printf 'CUSHION_SWAP=off\n' >"$W/conf"
	out=$(env "${ENV_COMMON[@]}" CUSHION_SWAP_CONFIG="$W/conf" SYSTEMCTL_BIN="$W/bin/systemctl" "$d" --wait-ready "$since" 2>&1)
	rc=$?
	[[ $rc == 0 && $out == *'CUSHION_SWAP=off'* ]] || { echo "  CUSHION_SWAP=off: exit $rc: $out"; ok=1; }
	return $ok
}

# U17: the postinst, run as a maintainer script would be, with systemd's tools answering: a failed
# step is said with its error, configuration goes on, and readiness is checked.
postinst_says_failures() {
	local ok=0 out rc pi=$POSTINST
	[[ -n $pi ]] || pi=$W/postinst.extracted
	if [[ ! -s $pi ]]; then
		sed -n "/^cat >\"\\\$D\/DEBIAN\/postinst\" <<'EOF'\$/,/^EOF\$/p" "$PKG/build.sh" | sed '1d;$d' >"$pi"
	fi
	mkdir -p "$W/pibin" "$W/pirun/systemd/system"
	printf '#!/bin/sh\necho "Failed to create directory /var/log/cushion-swap: Read-only file system" >&2\nexit 73\n' >"$W/pibin/systemd-tmpfiles"
	printf '#!/bin/sh\n[ "$1" = --quiet ] && exit 0\nexit 0\n' >"$W/pibin/deb-systemd-helper"
	printf '#!/bin/sh\necho "Job for cushion-swap.service failed." >&2\nexit 1\n' >"$W/pibin/deb-systemd-invoke"
	printf '#!/bin/sh\necho "cushion-swap $*" >>%s/pi.calls\n[ "$1" = --say ] && { shift; echo "said: $*" >&2; }\nexit 0\n' "$W" >"$W/pibin/cushion-swap"
	printf '#!/bin/sh\nexit 0\n' >"$W/pibin/systemctl"
	chmod +x "$W/pibin/"*
	rm -f "$W/pi.calls"
	# the script's absolute paths go to the fakes
	sed -e "s|/usr/sbin/cushion-swap|$W/pibin/cushion-swap|g" -e "s|-x /usr/bin/systemd-tmpfiles|-x $W/pibin/systemd-tmpfiles|" \
		-e "s|-d /run/systemd/system|-d $W/pirun/systemd/system|" "$pi" >"$W/postinst.run"
	out=$(PATH="$W/pibin:$PATH" sh "$W/postinst.run" configure 0.3.0 2>&1)
	rc=$?
	[[ $rc == 0 ]] || { echo "  the postinst failed the package: $rc"; ok=1; }
	[[ $out == *'said: LOCAL19 systemd-tmpfiles --create cushion-swap.conf 73 '*'Read-only file system'* ]] || { echo "  tmpfiles failure not said: $out"; ok=1; }
	[[ $out == *'said: LOCAL19 deb-systemd-invoke restart cushion-swap.service 1 Job for cushion-swap.service failed.'* ]] || { echo "  restart failure not said"; ok=1; }
	grep -q -- '--wait-ready [0-9]' "$W/pi.calls" || { echo "  readiness not checked"; ok=1; }
	return $ok
}

# The session's side: each kept problem once per session, critical when memory is not protected,
# in the session's language; a notification that cannot be shown is said.
notify_once() {
	local d=$1 ok=0 rc
	rm -rf "$W/state" "$W/xdg"
	mkdir -p "$W/xdg"
	meminfo "$W/m" 97957892 $((40 * G))
	swaps "$W/s"
	daemon MEMINFO_PATH="$W/m" SWAPS_PATH="$W/s" "$d" --once >/dev/null 2>&1
	printf '#!/bin/sh\nprintf "%%s|" "$@" >>%s/busctl.calls; echo >>%s/busctl.calls\n' "$W" "$W" >"$W/bin/busctl"
	chmod +x "$W/bin/busctl"
	rm -f "$W/busctl.calls"
	daemon BUSCTL_BIN="$W/bin/busctl" XDG_RUNTIME_DIR="$W/xdg" LANG=pt_BR.UTF-8 "$d" --notify
	rc=$?
	daemon BUSCTL_BIN="$W/bin/busctl" XDG_RUNTIME_DIR="$W/xdg" LANG=pt_BR.UTF-8 "$d" --notify
	[[ $rc == 0 && $(wc -l <"$W/busctl.calls") == 1 ]] || { echo "  shown $(wc -l <"$W/busctl.calls" 2>/dev/null) times"; ok=1; }
	grep -q 'A proteção da memória precisa de atenção|O Cushion Swap não consegue proteger a memória: nenhuma área de swap' "$W/busctl.calls" || { echo "  not in the session's language"; ok=1; }
	grep -q '|urgency|y|2|' "$W/busctl.calls" || { echo "  not critical"; ok=1; }
	printf '#!/bin/sh\necho "Failed to connect to bus: No medium found" >&2\nexit 1\n' >"$W/bin/busctl"
	rm -f "$W/xdg/cushion-swap-notified"
	daemon BUSCTL_BIN="$W/bin/busctl" XDG_RUNTIME_DIR="$W/xdg" "$d" --notify 2>"$W/log"
	rc=$?
	[[ $rc == 1 ]] && grep -q 'could not be shown (Failed to connect to bus: No medium found)' "$W/log" || { echo "  a failed notification was not said"; ok=1; }
	return $ok
}

# --problems in German with the English line beside it; exit 1 while a problem is kept.
problems_listed() {
	local d=$1 out rc
	out=$(daemon LANG=de_DE.UTF-8 "$d" --problems)
	rc=$?
	[[ $rc == 1 && $out == *'kein Auslagerungsbereich eingerichtet'* && $out == *'(en) Cushion Swap cannot protect memory'* ]]
}

# The unit keeps the status past the daemon and says why it stopped.
unit_says_why() {
	grep -qx 'ExecStopPost=/usr/sbin/cushion-swap --stopped' "$UNIT" && grep -qx 'RuntimeDirectoryPreserve=yes' "$UNIT" &&
		grep -qx 'NotifyAccess=all' "$UNIT"
}

# Every message in the nine languages, with the English one's placeholders.
messages_complete() {
	local lang key ok=0 n_en n
	for lang in pl pt_BR fr de ja ko zh_CN zh_TW; do
		[[ -r $PKG/lang/$lang ]] || { echo "  no $lang"; ok=1; continue; }
		while IFS= read -r key; do
			n_en=$(grep "^$key=" "$PKG/lang/en" | grep -o '%s' | wc -l)
			n=$(grep "^$key=" "$PKG/lang/$lang" | grep -o '%s' | wc -l)
			grep -q "^$key=\"" "$PKG/lang/$lang" && ((n == n_en)) || { echo "  $lang $key"; ok=1; }
		done < <(sed -n 's/^\(LOCAL[0-9]*\)=.*/\1/p' "$PKG/lang/en")
	done
	grep -ho 'LOCAL[0-9][0-9]*' "$PKG/sbin/cushion-swap" "$PKG/build.sh" | sort -u | while read -r key; do
		grep -q "^$key=" "$PKG/lang/en" || { echo "  $key used, not in en"; exit 1; }
	done || ok=1
	return $ok
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
	check problems-only-default problems_only_default "$d"
	check every-cycle-opt-in every_cycle_opt_in "$d"
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
	check calibration-idle-cache-invalidation calibration_cache "$d"
	check psi-fallback psi_fallback "$d"
	check daniel-harness-39 daniel_harness "$d"
	# ORDER 346b: nothing fails silently
	check protecting-control protecting_control "$d"
	check meminfo-unreadable meminfo_unreadable "$d"
	check swaps-unreadable swaps_unreadable "$d"
	check no-area-unprotected no_area_unprotected "$d"
	check deploy-failure-kept deploy_failure_kept "$d"
	check retract-failure-kept retract_failure_kept "$d"
	check status-exit-codes status_exit_codes "$d"
	check stopped-says-why stopped_says_why "$d"
	check psi-failures-said psi_failures_said "$d"
	check calibration-problems calibration_problems "$d"
	check hibernate-failures-kept hibernate_failures_kept "$d"
	check wait-ready wait_ready_cases "$d"
	check postinst-says-failures postinst_says_failures
	check notify-once notify_once "$d"
	check problems-listed problems_listed "$d"
	check unit-says-why unit_says_why
	check messages-complete messages_complete
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
if [[ ${CALIBRATION_ONLY:-} == 1 ]]; then
	check calibration-idle-cache-invalidation calibration_cache "${DAEMON_UNDER_TEST:-$PKG/sbin/cushion-swap}"
	echo "SUMMARY: $PASS passed, $FAIL failed (calibration only)"
	((FAIL == 0))
	exit
fi
check psi-helper-builds build_helper
[[ -x $W/psi-wake ]] || exit 1
check psi-helper-refuses-without-psi psi_helper_refuses
check game-performance-signal game_performance_signal
suite "${DAEMON_UNDER_TEST:-$PKG/sbin/cushion-swap}"
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
mutant headroom-ignored "headroom-pacing-default" 's/^\t((ms < floor_ms)) \&\& ms=\$floor_ms$/\tms=$max_ms/'
mutant headroom-ignores-game "compat-game-opening-headroom" 's/^\t((FAST_SINCE_MS)) \&\& cap_ms=\$FAST_MS$/\t:/'
# 3. an unused area, and Hibernate kept
mutant unused-area-kept "retract-unused-area hibernate-offered-after-retract" 's/ || area_empty) \&\& quiet_elapsed/) \&\& quiet_elapsed/'
mutant retract-during-hibernation "no-retract-while-hibernating" 's/ \&\& !hold))/))/'
mutant offered-only-while-on "hibernate-offered-after-retract" 's|^target=\$(value TARGET)$|target=$(value TARGET); grep -q "^$target[[:space:]]" "${SWAPS_PATH:-/proc/swaps}" \|\| exit 0|' generator
mutant skip-switch-on "hibernate-partition-not-in-fstab hibernate-swap-file-from-offset" 's/^\t\toutput=\$("\$SWAPON_BIN" -- "\$TARGET" 2>\&1)$/\t\toutput=""/'
# 4. logging
mutant actions-not-in-journal "actions-in-file-and-journal" 's/^\t((JOURNAL_TOO)) \&\& printf .%s\\n. "\$line" >\&2$/\t:/'
mutant noisy-default "problems-only-default" 's/^LOG_EVERY_CYCLE=\${LOG_EVERY_CYCLE:-no}$/LOG_EVERY_CYCLE=${LOG_EVERY_CYCLE:-yes}/'
mutant logrotate-absent "log-wiring logrotate-while-writing" absent logrotate
mutant logrotate-other-path "log-wiring logrotate-while-writing" 's|^/var/log/cushion-swap/cushion-swap.log {|/var/log/cushion-swap.log {|' logrotate
mutant unit-log-elsewhere "log-wiring" 's|^StandardOutput=append:.*|StandardOutput=journal|' unit
mutant unit-log-namespace "log-wiring" 's|^StandardError=journal$|StandardError=journal\nLogNamespace=cushion-swap|' unit
# 5. Hibernate from the installer's file
mutant ignore-the-file "generator-resume-sources hibernate-partition-not-in-fstab" 's/^\tif \[\[ -r \$INITRAMFS_RESUME_PATH \]\]; then$/\tif false; then/'
mutant hook-drops-offset "initramfs-hook-offset" 's/^echo "resume_offset=\$offset"/: "resume_offset=$offset"/' hook
# ORDER 346b: nothing fails silently
mutant problems-never-kept "meminfo-unreadable deploy-failure-kept calibration-problems" 's/^\t((DRY_RUN)) \&\& return 0$/\treturn 0/'
mutant unprotected-exits-0 "meminfo-unreadable no-area-unprotected" 's/^\tno) exit 2 ;;$/\tno) exit 0 ;;/'
mutant psi-loss-silent "psi-failures-said" 's/^\t\t\tproblem_set psi-lost degraded LOCAL8 "the trigger was lost: \$why"$/\t\t\t:/'
mutant calibration-failure-silent "calibration-problems" 's/^\tproblem_set calibration-failed notice LOCAL9 "\$1" "\$CONSERVATIVE_MIB_S" "\$CONSERVATIVE_MIB_S"$/\t:/'
mutant resume-swapoff-ignored "hibernate-failures-kept" 's/^\t\t\t\texit 1$/\t\t\t\texit 0/' 
echo "SUMMARY: $PASS passed, $FAIL failed"
echo "SUMMARY: $PASS passed, $FAIL failed" >"$OUT/summary.txt"
((FAIL == 0))
