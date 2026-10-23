#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The command line, the session script and the wrapper on fixture machines.
# BIN: folder with sparky-stereo-gpu-env and makefixture. SRC: the package source.
set -u
BIN=${BIN:?}
SRC=${SRC:?}
PRIMARY=${PRIMARY_GPU_SCRIPT:-}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { # name got expected
	if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi
}
for m in one a10 host bmc three; do "$BIN/makefixture" $m "$T/$m" || { echo "makefixture $m failed"; exit 1; }; done
export XDG_CONFIG_HOME=$T/config XDG_CONFIG_DIRS=$T/none XDG_DATA_HOME=$T/data XDG_DATA_DIRS=$T/usr
mkdir -p "$XDG_CONFIG_HOME" "$T/none"
env_for() { SPARKY_STEREO_GRAPHICS_ROOT=$T/$1 "$BIN/sparky-stereo-gpu-env" "${@:2}"; }

check "list: host has two lines" "$(env_for host --list | wc -l)" 2
check "list: the main GPU is marked" "$(env_for host --list | awk -F'\t' '$6=="main"{print $1}')" "pci-0000:0b:00.0"
check "list json" "$(env_for host --list --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d), d[1]["driver"], d[1]["kind"])')" "2 nvidia discrete"
check "list: three cards" "$(env_for three --list | wc -l)" 3
check "players balanced -> main GPU, no variables" "$(env_for host --category players --profile balanced | wc -l)" 0
check "players performance -> NVIDIA offload" "$(env_for host --category players --profile performance | head -2 | tr '\n' ' ')" "__GLX_VENDOR_LIBRARY_NAME=nvidia __NV_PRIME_RENDER_OFFLOAD=1 "
check "gpu name" "$(env_for host --category games --profile performance --print gpu)" "NVIDIA GeForce RTX 3060 Lite Hash Rate"
check "render node for a player on power-saver" "$(env_for host --category players --profile power-saver --print render-node)" "/dev/dri/renderD128"
check "render node for a player on performance" "$(env_for host --category players --profile performance --print render-node)" "/dev/dri/renderD129"
check "shell form quotes the star" "$(env_for host --category games --profile performance --shell | grep VK_LOADER)" "export VK_LOADER_DRIVERS_SELECT='*nvidia*'"
check "one GPU: nothing to export" "$(env_for one --category games --profile performance | wc -l)" 0
check "bad category exits 2" "$(env_for host --category nonsense >/dev/null 2>&1; echo $?)" 2
check "empty machine exits 1" "$(mkdir -p $T/empty; SPARKY_STEREO_GRAPHICS_ROOT=$T/empty "$BIN/sparky-stereo-gpu-env" --category games >/dev/null 2>&1; echo $?)" 1

# saved choices
printf '[General]\nMainGpu=pci-0000:01:00.0\n\n[Render]\nPlayers=integrated\nGames=discrete\n' >"$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
check "saved: session line" "$(env_for host --session)" "export KWIN_DRM_DEVICES='/dev/dri/card1:/dev/dri/card0'"
check "saved: players integrated while NVIDIA draws the desktop" "$(env_for host --category players --profile balanced | head -1)" "DRI_PRIME=pci-0000_0b_00_0"
check "saved: games discrete is the main GPU, no variables" "$(env_for host --category games --profile balanced | wc -l)" 0
rm "$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
check "automatic: no session line" "$(env_for host --session | wc -l)" 0

# the session script, alone and with the edition's own primary-gpu script after it
SESSION=$SRC/share/plasma-env/sparky-stereo-graphics.sh
run_session() { # root savedmain handset
	(
		unset KWIN_DRM_DEVICES
		[ -z "${3:-}" ] || export KWIN_DRM_DEVICES=$3
		export PATH=$BIN:$PATH SPARKY_STEREO_GRAPHICS_ROOT=$T/$1 SPARKY_STEREO_SYSFS=$T/$1/sys
		if [ -n "${2:-}" ]; then printf '[General]\nMainGpu=%s\n' "$2" >"$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"; else rm -f "$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"; fi
		. "$SESSION"
		[ -z "$PRIMARY" ] || . "$PRIMARY"
		echo "${KWIN_DRM_DEVICES:-unset}"
	)
}
check "session: Automatic on the workstation sets nothing" "$(run_session host '')" unset
check "session: saved RTX 3060" "$(run_session host pci-0000:01:00.0)" "/dev/dri/card1:/dev/dri/card0"
check "session: a value set by hand is kept" "$(run_session host pci-0000:01:00.0 /dev/dri/card0)" "/dev/dri/card0"
check "session: a GPU that is not here leaves Automatic" "$(run_session host pci-0000:09:00.0)" unset
check "session: one GPU, saved id of itself" "$(run_session one pci-0000:00:02.0)" "/dev/dri/card0"
if [ -n "$PRIMARY" ]; then
	check "with the edition's rule: BMC board, Automatic" "$(run_session bmc '')" "/dev/dri/card1:/dev/dri/card0"
	check "with the edition's rule: BMC board, the page chose the card" "$(run_session bmc pci-0000:65:00.0)" "/dev/dri/card1:/dev/dri/card0"
fi
check "session: command missing is harmless" "$( (unset KWIN_DRM_DEVICES; export PATH=/usr/bin:/bin; . "$SESSION"; echo "rc=$? ${KWIN_DRM_DEVICES:-unset}") )" "rc=0 unset"
rm -f "$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"

# the wrapper
RUN=$SRC/share/sparky-stereo-gpu-run
wrapped() { # root profile args...
	(export PATH=$BIN:$PATH SPARKY_STEREO_GRAPHICS_ROOT=$T/$1 SPARKY_STEREO_POWER_PROFILE=$2; shift 2; sh "$RUN" "$@")
}
check "wrapper: performance games get the offload" "$(wrapped host performance --category games env | grep -c '^__NV_PRIME_RENDER_OFFLOAD=1$')" 1
check "wrapper: the star arrives unexpanded" "$(wrapped host performance --category games env | grep '^VK_LOADER')" "VK_LOADER_DRIVERS_SELECT=*nvidia*"
check "wrapper: balanced adds nothing" "$(wrapped host balanced --category games env | grep -c -E '^(DRI_PRIME|__NV_PRIME)')" 0
check "wrapper: arguments are passed on" "$(wrapped host balanced --category games printf '%s|' a 'b c')" "a|b c|"
check "wrapper: no option, the command runs" "$(wrapped host balanced printf ok)" ok
check "wrapper: -- ends the options" "$(wrapped host performance -- printf ok)" ok
check "wrapper: no command exits 2" "$(wrapped host balanced >/dev/null 2>&1; echo $?)" 2
check "wrapper: option without value exits 2" "$(wrapped host balanced --category >/dev/null 2>&1; echo $?)" 2
check "wrapper: a broken choice never stops the program" "$( (export PATH=$T/broken:/usr/bin:/bin; mkdir -p $T/broken; printf '#!/bin/sh\nexit 1\n' >$T/broken/sparky-stereo-gpu-env; chmod +x $T/broken/sparky-stereo-gpu-env; sh "$RUN" --category games printf ran) )" ran
check "wrapper: no sparky-stereo-gpu-env at all" "$( (export PATH=/usr/bin:/bin; sh "$RUN" --category games printf ran) )" ran
echo "cli: $pass passed, $fail failed"
[ "$fail" = 0 ]
