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
# players, and programs in 3D, on the GPU measured best whatever the profile; not measured: the discrete GPU
for p in power-saver balanced performance; do
	check "players $p, not measured -> NVIDIA offload" "$(env_for host --category players --profile $p | head -2 | tr '\n' ' ')" "__GLX_VENDOR_LIBRARY_NAME=nvidia __NV_PRIME_RENDER_OFFLOAD=1 "
	check "players $p, not measured: the reason" "$(env_for host --category players --profile $p --print reason)" unmeasured
	check "a10 players $p -> the R5 M430" "$(env_for a10 --category players --profile $p --print render-node)" "/dev/dri/renderD129"
done
check "browsers balanced -> main GPU, no variables" "$(env_for host --category browsers --profile balanced | wc -l)" 0
# split by kind (Daniel, 2026-10-24): other programs on the GPU that draws the desktop in every profile, browsers by the profile, games measured
for p in power-saver balanced performance; do
	check "other $p -> the desktop's GPU, no variables" "$(env_for host --category other --profile $p | wc -l) $(env_for host --category other --profile $p --print reason)" "0 desktop"
	check "a10 games $p -> the R5 M430" "$(env_for a10 --category games --profile $p --print render-node)" "/dev/dri/renderD129"
done
check "browsers performance -> NVIDIA offload" "$(env_for host --category browsers --profile performance | grep -c '^__NV_PRIME_RENDER_OFFLOAD=1$')" 1
check "a10 browsers on battery: integrated" "$(env_for a10 --category browsers --profile power-saver --print render-node)" "/dev/dri/renderD128"
check "gpu name" "$(env_for host --category games --profile performance --print gpu)" "NVIDIA GeForce RTX 3060 Lite Hash Rate"
check "a10 browsers on battery started in 3D: the R5 M430" "$(env_for a10 --category browsers --3d --profile power-saver --print render-node)" "/dev/dri/renderD129"
check "a10 any program started in 3D" "$(env_for a10 --3d --profile power-saver --print render-node)" "/dev/dri/renderD129"
check "follow the power profile, a player on battery" "$(env_for a10 --choice profile --profile power-saver --print render-node)" "/dev/dri/renderD128"
check "follow the power profile, on performance" "$(env_for a10 --choice profile --profile performance --print render-node)" "/dev/dri/renderD129"
# a desktop file outside the menu (a launcher on the desktop), as Plasma's launcher asks for it
mkdir -p "$T/Desktop"
printf '[Desktop Entry]\nType=Application\nName=Player\nExec=true\nCategories=AudioVideo;Video;Player;\n' >"$T/Desktop/player.desktop"
printf '[Desktop Entry]\nType=Application\nName=Game\nExec=true\nCategories=Game;\n' >"$T/Desktop/game.desktop"
printf '[Desktop Entry]\nType=Application\nName=Browser\nExec=true\nCategories=Network;WebBrowser;\n' >"$T/Desktop/browser.desktop"
printf '[Desktop Entry]\nType=Application\nName=Music\nExec=true\nCategories=Qt;KDE;Audio;AudioVideo;\n' >"$T/Desktop/music.desktop"
check "a10 player outside the menu, on battery: the R5 M430" "$(env_for a10 --app "$T/Desktop/player.desktop" --profile power-saver --print render-node)" "/dev/dri/renderD129"
check "a10 game outside the menu, on battery: the R5 M430" "$(env_for a10 --app "$T/Desktop/game.desktop" --profile power-saver --print render-node)" "/dev/dri/renderD129"
check "a10 browser outside the menu, on battery: integrated" "$(env_for a10 --app "$T/Desktop/browser.desktop" --profile power-saver --print render-node)" "/dev/dri/renderD128"
check "a10 browser outside the menu, on performance" "$(env_for a10 --app "$T/Desktop/browser.desktop" --profile performance | head -1)" "DRI_PRIME=pci-0000_03_00_0"
check "an audio player (Audio without Video) is another program" "$(env_for a10 --app "$T/Desktop/music.desktop" --profile performance | wc -l) $(env_for a10 --app "$T/Desktop/music.desktop" --print reason)" "0 desktop"
check "a desktop file that is not there exits 2" "$(env_for a10 --app "$T/Desktop/missing.desktop" >/dev/null 2>&1; echo $?)" 2
check "shell form quotes the star" "$(env_for host --category games --profile performance --shell | grep VK_LOADER)" "export VK_LOADER_DRIVERS_SELECT='*nvidia*'"
check "one GPU: nothing to export" "$(env_for one --category games --profile performance | wc -l)" 0
check "bad category exits 2" "$(env_for host --category nonsense >/dev/null 2>&1; echo $?)" 2
check "empty machine exits 1" "$(mkdir -p $T/empty; SPARKY_STEREO_GRAPHICS_ROOT=$T/empty "$BIN/sparky-stereo-gpu-env" --category games >/dev/null 2>&1; echo $?)" 1

# saved choices
printf '[General]\nMainGpu=pci-0000:01:00.0\n\n[Render]\nPlayers=integrated\nGames=discrete\n' >"$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
check "saved: session line" "$(env_for host --session)" "export KWIN_DRM_DEVICES='/dev/dri/card1:/dev/dri/card0'"
check "saved: players integrated while NVIDIA draws the desktop" "$(env_for host --category players --profile balanced | head -1)" "DRI_PRIME=pci-0000_0b_00_0"
check "saved: NVIDIA draws the desktop, so Mesa's EGL and GLX are named" "$(env_for host --category players --profile balanced | grep -E '^__(EGL|GLX)_VENDOR' | tr '\n' ' ')" "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json __GLX_VENDOR_LIBRARY_NAME=mesa "
check "saved: games discrete is the main GPU, no variables" "$(env_for host --category games --profile balanced | wc -l)" 0
rm "$XDG_CONFIG_HOME/sparky-stereo-graphicsrc"
check "automatic: no session line" "$(env_for host --session | wc -l)" 0

# the machine record: sparky-stereo-gpu-record writes it (as root, under --root here), the command reads it
REC=$BIN/sparky-stereo-gpu-record
MACHINES=$SRC/share/machines
record() { "$REC" --root "$T/$1" --machines "$MACHINES" "${@:2}"; }
check "record: the A10 is a known model" "$(record a10 --apply-known)" written
check "record: written to the system folder" "$(grep -c '^BestGpu=1002:6660$' "$T/a10/etc/xdg/sparky-stereo-graphicsrc")" 1
check "record: shown" "$(record a10 --show | grep -E '^(origin|best-gpu|copy-back)=' | tr '\n' ' ')" "origin=shipped best-gpu=1002:6660 copy-back=false "
check "record: the next boot changes nothing" "$(record a10 --apply-known)" unchanged
check "record: the workstation is not known" "$(record host --apply-known) $(test -e "$T/host/etc/xdg/sparky-stereo-graphicsrc"; echo $?)" "nothing-known 1"
with_record() { XDG_CONFIG_DIRS=$T/$1/etc/xdg env_for "$@"; }
check "record: the command reads it" "$(with_record a10 --category players --profile power-saver --print reason)" measured
# a record that names the APU on the workstation keeps players there even on performance
mkdir -p "$T/host/etc/xdg"
check "record: a measurement's result" "$(record host --set-best 1002:1638 --measurement 'bench'; echo $?)" 0
check "record: the measured APU, on performance" "$(with_record host --category players --profile performance --print render-node)" "/dev/dri/renderD128"
check "record: a measured record is kept at boot" "$(record host --apply-known)" kept
check "record: copy-back for the machine" "$(record host --copy-back true; grep -c '^CopyBack=true$' "$T/host/etc/xdg/sparky-stereo-graphicsrc")" 1
check "record: forget" "$(record host --forget; test -e "$T/host/etc/xdg/sparky-stereo-graphicsrc"; echo $?)" 1
check "record: the disk moved to another machine" "$(cp "$T/a10/etc/xdg/sparky-stereo-graphicsrc" "$T/host/etc/xdg/"; record host --apply-known)" removed
check "record: not a GPU exits 2" "$(record host --set-best fastest >/dev/null 2>&1; echo $?)" 2
check "record: no action exits 2" "$(record host >/dev/null 2>&1; echo $?)" 2
check "record: a folder it cannot write exits 3" "$(mkdir -p "$T/ro/etc"; chmod 555 "$T/ro/etc"; "$REC" --root "$T/ro" --set-best 1002:6660 >/dev/null 2>&1; echo $?; chmod 755 "$T/ro/etc")" 3

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
check "wrapper: balanced adds nothing" "$(wrapped host balanced --category browsers env | grep -c -E '^(DRI_PRIME|__NV_PRIME)')" 0
check "wrapper: a browser started in 3D on battery" "$(wrapped a10 power-saver --category browsers --3d env | grep '^DRI_PRIME')" "DRI_PRIME=pci-0000_03_00_0"
check "wrapper: --3d first" "$(wrapped a10 power-saver --3d --category browsers env | grep '^DRI_PRIME')" "DRI_PRIME=pci-0000_03_00_0"
check "wrapper: the same browser in 2D" "$(wrapped a10 power-saver --category browsers env | grep -c '^DRI_PRIME')" 0
check "wrapper: a game on battery on the R5 M430" "$(wrapped a10 power-saver --category games env | grep '^DRI_PRIME')" "DRI_PRIME=pci-0000_03_00_0"
check "wrapper: arguments are passed on" "$(wrapped host balanced --category games printf '%s|' a 'b c')" "a|b c|"
check "wrapper: no option, the command runs" "$(wrapped host balanced printf ok)" ok
check "wrapper: -- ends the options" "$(wrapped host performance -- printf ok)" ok
check "wrapper: no command exits 2" "$(wrapped host balanced >/dev/null 2>&1; echo $?)" 2
check "wrapper: option without value exits 2" "$(wrapped host balanced --category >/dev/null 2>&1; echo $?)" 2
check "wrapper: a broken choice never stops the program" "$( (export PATH=$T/broken:/usr/bin:/bin; mkdir -p $T/broken; printf '#!/bin/sh\nexit 1\n' >$T/broken/sparky-stereo-gpu-env; chmod +x $T/broken/sparky-stereo-gpu-env; sh "$RUN" --category games printf ran) )" ran
check "wrapper: no sparky-stereo-gpu-env at all" "$( (export PATH=/usr/bin:/bin; sh "$RUN" --category games printf ran) )" ran
echo "cli: $pass passed, $fail failed"
[ "$fail" = 0 ]
