#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# The Graphics page names the GPU players use (sparky-stereo-gpu-env --category players). A caller that
# copies its decoded pictures back decodes there, and on another GPU only where the person allows it
# ([Decoding] OtherGpu, MEDIA_GPU_ROUTE_OTHER_GPU); a page that fails, answers nothing or names a GPU that
# is not here is said and nothing decodes on another GPU (ORDER 346a). A caller that imports decoded
# surfaces, and media_gpu_route_default, keep the graphics stack's order: the renderer draws on the GPU
# the program was started on. Needs two GPUs that decode H.264 in the container; a fake
# sparky-stereo-gpu-env stands in for the page. With AV1=1, one of them must decode AV1 and the other not.
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
unresolved() { run MEDIA_GPU_ROUTE_COPY_BACK=true "$@" "$QUERY" --decoder h264 100 8 1920x1080 copy 2>/dev/null; }
fake "echo /dev/dri/renderD999"
check "page names a GPU that is not here: said, no other GPU" "$(unresolved)" "result=unresolved"
fake "exit 4"
check "page cannot use the chosen GPU: said, no other GPU" "$(unresolved)" "result=unresolved"
fake ":"
check "page answers nothing: said, no other GPU" "$(unresolved)" "result=unresolved"
if [ "${AV1:-}" = 1 ]; then
	# AV1: the GPU that cannot decode it is named for players; another GPU decodes it only where the person allows it
	av1() { run MEDIA_GPU_ROUTE_COPY_BACK=true "$@" "$QUERY" --decoder av1 0 8 1920x1080 copy 2>"$T/av1-err"; }
	rm -rf "$T/bin"
	able=$(av1 | sed -n 's/^result=hardware .* gpu=//p')
	unable=
	for node in $nodes; do [ "$(name_of "$node")" = "$able" ] || unable=$node; done
	[ -n "$able" ] && [ -n "$unable" ] || { echo "SKIP: no pair of GPUs where one decodes AV1 and one not"; exit 77; }
	fake "echo $unable"
	check "AV1, the players' GPU cannot decode it: software" "$(av1)" "result=software"
	check "AV1, the players' GPU cannot decode it: said" "$(grep -c 'cannot decode this video in hardware' "$T/av1-err")" 1
	check "AV1, another GPU where the person allows it" "$(av1 MEDIA_GPU_ROUTE_OTHER_GPU=true | sed -n 's/^result=hardware .* gpu=//p')" "$able"
	check "AV1, another GPU where the person allows it: said" "$(grep -c 'as Decode on another GPU allows' "$T/av1-err")" 1
fi
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
