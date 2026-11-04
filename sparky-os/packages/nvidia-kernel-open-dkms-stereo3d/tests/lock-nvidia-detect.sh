#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# A driver lock keeps Debian's real nvidia-detect: its first record names nvidia-detect from Debian's archive at a
# priority above the lock's 1005, ahead of the src:nvidia-graphics-drivers records (apt_preferences(5): the first
# specific-form record matching an available package version determines its priority).
# Usage: lock-nvidia-detect.sh LOCK.deb
set -euo pipefail
deb=$(realpath "${1:?lock .deb}")
file=$(dpkg-deb --fsys-tarfile "$deb" | tar -t | grep -E '/etc/apt/preferences.d/[^/]+$' | head -n1)
text=$(dpkg-deb --fsys-tarfile "$deb" | tar -xO "$file")
first=$(printf '%s\n' "$text" | awk '/^Package:/ {print; exit}')
[ "$first" = "Package: nvidia-detect" ] || { echo "first record is not nvidia-detect: $first" >&2; exit 1; }
printf '%s\n' "$text" | awk '/^Package:/ {n++} n==1' | grep -qx 'Pin: release o=Debian'
printf '%s\n' "$text" | awk '/^Package:/ {n++} n==1' | grep -qx 'Pin-Priority: 1010'
! printf '%s\n' "$text" | awk '/^Package: nvidia-detect/ {next} /^Package:/ {p=1} p' | grep -q 'nvidia-detect'
echo "ok: $file"
