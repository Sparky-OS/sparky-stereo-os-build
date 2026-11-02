#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# ORDER 346a, U25: when the GPU chosen for players cannot be resolved (the Graphics page's command fails, answers
# nothing, or names a GPU this program cannot open), the decoder choice says so and decodes on no other GPU; the 0.2
# entry point answers software and says it on stderr. Runs without any GPU: a fake sparky-stereo-gpu-env answers.
# Usage: unresolved.sh PATH-TO-media-gpu-route-query PATH-TO-old-api-test
set -u
QUERY=${1:?}
OLDAPI=${2:?}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
has() { if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: '$3' not in: $(head -c 400 "$2")"; fi; }
fake() { mkdir -p "$T/bin"; printf '#!/bin/sh\n%s\n' "$1" >"$T/bin/sparky-stereo-gpu-env"; chmod +x "$T/bin/sparky-stereo-gpu-env"; }
unset LANGUAGE LC_ALL LC_MESSAGES DRI_PRIME MESA_VK_DEVICE_SELECT VK_LOADER_DRIVERS_SELECT __NV_PRIME_RENDER_OFFLOAD
run() { env PATH="$T/bin:/usr/bin:/bin" LANG=C.UTF-8 XDG_CONFIG_HOME="$T/none" XDG_CONFIG_DIRS="$T/none" MEDIA_GPU_ROUTE_COPY_BACK=true "$@"; }
copy() { run "$@" "$QUERY" --decoder h264 100 8 1920x1080 copy 2>"$T/err"; }
check "no page installed: nothing to resolve" "$(copy)" "result=unknown"
fake "echo 'sparky-stereo-gpu-env: the GPU chosen for players is not here' >&2; exit 4"
check "the chosen GPU cannot be used: unresolved, no other GPU" "$(copy)" "result=unresolved"
has "the chosen GPU cannot be used: said" "$T/err" "the GPU chosen for players in System Settings, Graphics could not be resolved (sparky-stereo-gpu-env exit status 4). This video is decoded in software, on no other GPU."
has "the chosen GPU cannot be used: the page's own words too" "$T/err" "sparky-stereo-gpu-env: the GPU chosen for players is not here"
fake "echo /dev/dri/renderD999"
check "the page names a GPU this program cannot open: unresolved" "$(copy)" "result=unresolved"
has "the page names a GPU this program cannot open: said" "$T/err" "(/dev/dri/renderD999) is not among the GPUs this program can open"
fake ":"
check "the page answers nothing: unresolved" "$(copy)" "result=unresolved"
fake "exit 3"
check "in German" "$(copy LANG=de_DE.UTF-8 >/dev/null; grep -c 'konnte nicht ermittelt werden (Exit-Status von sparky-stereo-gpu-env 3)' "$T/err")" 1
check "in Japanese" "$(copy LANGUAGE=ja >/dev/null; grep -c '特定できませんでした' "$T/err")" 1
check "in Traditional Chinese" "$(copy LANG=zh_TW.UTF-8 >/dev/null; grep -c '無法確定' "$T/err")" 1
check "a GPU chosen at launch: the page is not asked" "$(copy DRI_PRIME=1)" "result=unknown"
check "copying back not allowed: software, the page not asked" "$(env PATH="$T/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$T/none" XDG_CONFIG_DIRS="$T/none" "$QUERY" --decoder h264 100 8 1920x1080 copy 2>/dev/null)" "result=software"
check "an importing caller: the page is not asked" "$(run "$QUERY" --decoder h264 100 8 1920x1080 import 2>/dev/null)" "result=unknown"
# the 0.2 entry point that MLT and VLC call: software, never another GPU (-1 sends them to the default route)
check "0.2 entry point, unresolved: software" "$(run "$OLDAPI" 2>"$T/err")" "result=0"
has "0.2 entry point, unresolved: said on stderr" "$T/err" "media-gpu-route: the GPU chosen for players in System Settings, Graphics could not be resolved"
echo "unresolved: $pass passed, $fail failed"
[ "$fail" = 0 ]
