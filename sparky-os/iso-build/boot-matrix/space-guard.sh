#!/bin/sh
# Pauses a test VM (QMP stop) when a disk's free space falls to its floor plus 1 GB, and logs it.
#   space-guard.sh QMP_SOCKET LOG [MOUNT] [FLOOR_GB]     (default: /K3D and its floor, 5 GB)
# The VM's disk image grows while it installs; the guard stops it before the floor is crossed.
Q=$1; LOG=$2; M=${3:-/K3D}; FLOOR=${4:-5}
HERE=$(cd "$(dirname "$0")" && pwd)
while [ -S "$Q" ]; do
	free=$(df -BG --output=avail "$M" | tail -1 | tr -dc 0-9)
	if [ "$free" -le $((FLOOR + 1)) ]; then
		python3 "$HERE/vmctl.py" "$Q" hmp stop >/dev/null 2>&1
		echo "$(date -u +%T) $M at ${free} GB: VM paused" >> "$LOG"; exit 1
	fi
	sleep 30
done
