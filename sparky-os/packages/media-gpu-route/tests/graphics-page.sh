#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# The Graphics page names the GPU players use (sparky-stereo-gpu-env --category players). A caller that
# copies its decoded pictures back decodes there first, every other GPU behind it, so a source it cannot
# decode still falls back. A caller that imports decoded surfaces, and media_gpu_route_default, keep the
# graphics stack's order: the renderer draws on the GPU the program was started on. Needs two GPUs that
# decode H.264 in the container; a fake sparky-stereo-gpu-env stands in for the page.
# Usage: graphics-page.sh PATH-TO-media-gpu-route-query
set -u
QUERY=${1:?}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
fake() { # fake HELPER-BODY: a sparky-stereo-gpu-env that answers as the page would, and notes that it was asked
	mkdir -p "$T/bin"
	printf '#!/bin/sh\necho asked >>"%s/asked"\n%s\n' "$T" "$1" >"$T/bin/sparky-stereo-gpu-env"
	chmod +x "$T/bin/sparky-stereo-gpu-env"
	rm -f "$T/asked"
}
run() { env PATH="$T/bin:/usr/bin:/bin" XDG_CONFIG_HOME="$T/none" XDG_CONFIG_DIRS="$T/none" "$@"; }
copy() { run MEDIA_GPU_ROUTE_COPY_BACK=true "$@" "$QUERY" --decoder h264 100 8 1920x1080 copy | sed -n 's/^result=hardware .* gpu=//p'; }
import() { run "$@" "$QUERY" --decoder h264 100 8 1920x1080 import | sed -n 's/^result=hardware .* gpu=//p'; }
default() { run "$@" "$QUERY" | sed -n 's/^.* node=\([^ ]*\) .*/\1/p'; }
rm -rf "$T/bin"
caps=$(run "$QUERY" --capabilities)
echo "$caps"
nodes=$(sed -n 's/^gpu=[0-9]* .* node=\([^ ]*\) .*/\1/p' <<<"$caps")
count=$(wc -w <<<"$nodes")
if [ "$count" -lt 2 ]; then echo "SKIP: needs two GPUs"; exit 77; fi
name_of() { sed -n "s|^gpu=[0-9]* .* node=$1 .* name=||p" <<<"$caps"; }
copy0=$(copy)
import0=$(import)
default0=$(default)
[ -n "$copy0" ] && [ -n "$import0" ] || { echo "SKIP: no hardware H.264 decoder"; exit 77; }
check "no page: the copy caller decodes on the first GPU" "$copy0" "$(name_of "${nodes%%$'\n'*}")"
for node in $nodes; do
	fake "echo $node"
	check "page names $node: a copy caller decodes there" "$(copy)" "$(name_of "$node")"
	check "page names $node: the page was asked" "$(cat "$T/asked" 2>/dev/null)" asked
	check "page names $node: an importing caller keeps the renderer's GPU" "$(import)" "$import0"
	check "page names $node: the default stays the graphics stack's" "$(default)" "$default0"
done
last=$(tail -1 <<<"$nodes")
fake "echo /dev/dri/renderD999"
check "page names a GPU that is not here: unchanged" "$(copy)" "$copy0"
fake "exit 1"
check "page fails: unchanged" "$(copy)" "$copy0"
fake ":"
check "page answers nothing: unchanged" "$(copy)" "$copy0"
fake "echo $last"
check "copying back not allowed: software, and the page is not asked" "$(run "$QUERY" --decoder h264 100 8 1920x1080 copy):$(cat "$T/asked" 2>/dev/null)" "result=software:"
# a GPU chosen at launch is more specific than the page: Mesa orders the list and the page is not asked
for assignment in DRI_PRIME=1 MESA_VK_DEVICE_SELECT=1002:1638; do
	rm -rf "$T/bin"
	expected=$(copy "$assignment")
	fake "echo $last"
	check "$assignment set at launch: the page is not asked" "$(copy "$assignment"):$(cat "$T/asked" 2>/dev/null)" "$expected:"
done
echo "graphics-page: $pass passed, $fail failed"
[ "$fail" = 0 ]
