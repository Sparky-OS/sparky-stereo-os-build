#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Records /sys/class/hwmon of this machine as plain files (read only: nothing is written to the machine): every readable regular file of each hwmonN folder, one
# level deep, sizes under 64 bytes, no symlink followed. The daemon's tests below play it back as a recorded machine. Usage: record-hwmon.sh OUT.tar.xz
set -euo pipefail
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/hwmon"
for h in /sys/class/hwmon/hwmon*; do
	n=$(basename "$h"); mkdir "$W/hwmon/$n"
	for f in "$h"/*; do
		[ -f "$f" ] && [ ! -L "$f" ] || continue
		[ "$(stat -c %s "$f")" -le 4096 ] || continue
		cat "$f" >"$W/hwmon/$n/$(basename "$f")" 2>/dev/null || true
	done
done
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -C "$W" -cJf "$1" hwmon
tar -tJf "$1" | wc -l
