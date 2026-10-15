#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/15
# Tests share/plasma-env/sparky-stereo-primary-gpu.sh on fixture sysfs trees.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
card() { # card SYS N BOOTVGA RENDER(0/1) STATUS...
	s=$1 n=$2; c=$s/class/drm/card$n; d=$s/devices/pci$n
	mkdir -p "$d/drm/card$n" "$c"; ln -s "$d" "$c/device"; echo "$3" > "$d/boot_vga"
	[ "$4" = 1 ] && mkdir -p "$d/drm/renderD$((128 + n))"
	shift 4; i=0
	for st in "$@"; do i=$((i + 1)); mkdir -p "$s/class/drm/card$n-DP-$i"; echo "$st" > "$s/class/drm/card$n-DP-$i/status"; done
}
run() { (unset KWIN_DRM_DEVICES; SPARKY_STEREO_SYSFS=$1; . "$HERE/share/plasma-env/sparky-stereo-primary-gpu.sh"; echo "${KWIN_DRM_DEVICES:-unset}"); }
s=$T/one; card $s 0 1 1 connected
check "one card that renders" "$(run $s)" unset
s=$T/bmc; card $s 0 1 0 connected; card $s 1 0 1 connected disconnected
check "BMC boot VGA and an NVIDIA card with a screen" "$(run $s)" "/dev/dri/card1:/dev/dri/card0"
s=$T/two; card $s 0 1 0 disconnected; card $s 1 0 1 disconnected; card $s 2 0 1 connected
check "BMC and two cards, the screen on the second" "$(run $s)" "/dev/dri/card2:/dev/dri/card1:/dev/dri/card0"
s=$T/nvboot; card $s 0 0 0 connected; card $s 1 1 1 connected
check "the card that renders is the boot VGA" "$(run $s)" unset
s=$T/bmconly; card $s 0 1 0 connected
check "BMC only" "$(run $s)" unset
check "a KWIN_DRM_DEVICES set by the person is kept" "$(KWIN_DRM_DEVICES=/dev/dri/card0; SPARKY_STEREO_SYSFS=$T/bmc; . "$HERE/share/plasma-env/sparky-stereo-primary-gpu.sh"; echo $KWIN_DRM_DEVICES)" /dev/dri/card0
echo "primary-gpu: $pass passed, $fail failed"
[ "$fail" = 0 ]
