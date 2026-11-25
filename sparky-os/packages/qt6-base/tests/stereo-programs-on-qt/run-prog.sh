#!/bin/bash
# run-prog.sh NAME IMAGE RESULTS [KEY=VALUE ...] -- host side: one fresh container and Stereo KWin session for one
# program case of row 863 part A (prog-case.sh inside). KEY=VALUE words are passed into the container's environment
# (PROG, PROGENV, PRESETUP, PROBE, EXT_STEPS, R863_*...). GPU=amd (default, the AMD render node: single cases) or
# GPU=nvidia (the NVIDIA card through CDI). PROBE_SO is the built r863-probe.so; FILES a folder mounted at /files (a
# film, a document). CASE_SCRIPT runs another case script of this folder (frame-case.sh). ROW863_CONTAINER_IDS gets each container's ID. --cpus 4, --network none, --ulimit core=1, uid 1000.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
NAME=$1 IMAGE=$2 RESULTS=$3; shift 3
OUT=$RESULTS/$NAME; rm -rf "$OUT"; mkdir -p "$OUT"
PROOFRIG=${PROOFRIG:-/var/lib/sparky-lanes/science-50i/kept-freecad/proofrig}
envs=() gpu=(--device /dev/dri/renderD128 --group-add 125)
for kv in "$@"; do
	case $kv in
	GPU=nvidia) gpu=(--device nvidia.com/gpu=0 --device /dev/dri/renderD129:/dev/dri/renderD128 --group-add 125) ;;
	GPU=*) ;;
	*) envs+=(-e "$kv") ;;
	esac
done
extra=()
[ -n "${PROBE_SO:-}" ] && extra+=(--mount "type=bind,src=$(dirname "$(readlink -f "$PROBE_SO")"),dst=/probe,readonly")
[ -n "${FILES:-}" ] && extra+=(--mount "type=bind,src=$(readlink -f "$FILES"),dst=/files,readonly")
cid=$RESULTS/.cid-$NAME; rm -f "$cid"
docker run --rm --init --cidfile "$cid" --name "sc50i-a863-$NAME" --pull=never --ulimit core=1 --cpus 4 --network none \
	--user 1000:1000 --cap-add SYS_NICE --shm-size 1g "${gpu[@]}" "${extra[@]}" \
	--mount "type=bind,src=$HERE,dst=/tests,readonly" --mount "type=bind,src=$PROOFRIG,dst=/proofrig,readonly" \
	--mount "type=bind,src=$OUT,dst=/out" "${envs[@]}" "$IMAGE" \
	dbus-run-session -- bash -c "timeout ${CASE_LIMIT:-600} bash /tests/${CASE_SCRIPT:-prog-case.sh}" > "$OUT/container.log" 2>&1 \
	|| echo "container rc=$?" >> "$OUT/container.log"
if [ -n "${ROW863_CONTAINER_IDS:-}" ] && [ -s "$cid" ]; then { cat "$cid"; echo; } >> "$ROW863_CONTAINER_IDS"; fi
rm -f "$cid"
echo "$OUT"
