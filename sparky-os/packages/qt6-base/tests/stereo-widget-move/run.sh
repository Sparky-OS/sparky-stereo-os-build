#!/bin/bash
# run.sh IMAGE RESULTS [LIBDIR] -- queue row 863's test of qt6-base: a stereo QOpenGLWidget under alien ancestors whose
# window must move while the window repaints (a scroll area, a graphics view's viewport beside a dock, an item view's
# cell widget, a dock floated and docked again). One fresh container and Stereo KWin session per case.
#   IMAGE   an image with the Qt build under test installed (its libqt6* and qt6-base-dev), Stereo KWin (kwin-wayland),
#           Mesa, valgrind, g++, python3 and bc: the edition's published tree with the build's packages over it
#   RESULTS an empty folder: bin/ (the test, compiled in IMAGE), one folder per case, verdicts.txt
#   LIBDIR  optional: a folder of development libraries put first (LD_LIBRARY_PATH) over IMAGE's Qt
# Rows (one per claim; exit 1 when a row is not as expected):
#   memcheck-MODE  no read of a freed QPlatformTextureList, every step placed, the run ended by itself
#   lag-MODE       every step placed; the commits of the top level that carried the stereo window elsewhere than its
#                  widget, and how many of those reached the screen (reported; the expectation is ROW863_LAG_MAX, by
#                  default no limit, so the number is measured, not judged)
# The KWin session draws on the NVIDIA card through CDI when GPU=nvidia (loops belong there), else the AMD render node;
# the test program always draws with llvmpipe. ROW863_OUTPUT_SCALE: the output's scale (case.sh's OUTPUT_SCALE).
# --cpus 4, --network none, --ulimit core=1, uid 1000.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=$1 RESULTS=$(mkdir -p "$2" && cd "$2" && pwd -P) LIBDIR=${3:-}
[ -z "$(ls -A "$RESULTS")" ] || { echo "$RESULTS is not empty" >&2; exit 2; }
PREFIX=${ROW863_CONTAINER_PREFIX:-qt6-base-test}
CIDS=${ROW863_CONTAINER_IDS:-}
MODES=${ROW863_MODES:-scroll viewport itemview float}
echo "load at start: $(cut -d' ' -f1-3 /proc/loadavg)" | tee "$RESULTS/load.txt"
gpu=(--device /dev/dri/renderD128 --group-add 125)
[ "${GPU:-amd}" = nvidia ] && gpu=(--device nvidia.com/gpu=0 --device /dev/dri/renderD129:/dev/dri/renderD128 --group-add 125)
lib=(); [ -n "$LIBDIR" ] && lib=(--mount "type=bind,src=$(cd "$LIBDIR" && pwd -P),dst=/variant,readonly" -e LIBDIR=/variant)
[ -n "${ROW863_OUTPUT_SCALE:-}" ] && lib+=(-e "OUTPUT_SCALE=$ROW863_OUTPUT_SCALE")
docker image inspect "$IMAGE" > /dev/null
run() { # NAME COMMAND...
	local name=$PREFIX-$1; shift
	local cid=$RESULTS/.cid-$name
	docker run --rm --init --cidfile "$cid" --name "$name" --pull=never --ulimit core=1 --cpus 4 --network none \
		--user 1000:1000 --cap-add SYS_NICE --shm-size 512m "${gpu[@]}" "${lib[@]}" \
		--mount "type=bind,src=$HERE,dst=/tests,readonly" --mount "type=bind,src=$RESULTS,dst=/out" \
		"$IMAGE" "$@" || echo "container $name rc=$?" >> "$RESULTS/containers.txt"
	if [ -n "$CIDS" ] && [ -s "$cid" ]; then { cat "$cid"; echo; } >> "$CIDS"; fi
	rm -f "$cid"
}
# the test is compiled in the image against the Qt it holds
run build bash -c 'mkdir -p /out/bin && g++ -O1 -g -fPIC -std=c++17 -o /out/bin/stereo-widget-move /tests/stereo-widget-move.cpp \
	$(pkg-config --cflags --libs Qt6Widgets Qt6OpenGLWidgets Qt6OpenGL) > /out/bin/build.log 2>&1; echo "build rc=$?" >> /out/bin/build.log'
grep -q 'build rc=0' "$RESULTS/bin/build.log" || { cat "$RESULTS/bin/build.log"; exit 1; }
for mode in $MODES; do
	run "memcheck-$mode" timeout 1800 bash /tests/case.sh memcheck "$mode" "${ROW863_MEMCHECK_STEPS:-24}" "${ROW863_MEMCHECK_WAIT:-700}"
	run "lag-$mode" timeout 600 bash /tests/case.sh lag "$mode" "${ROW863_LAG_STEPS:-60}" "${ROW863_LAG_WAIT:-150}"
done
echo "load at end: $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$RESULTS/load.txt"
python3 -I "$HERE/verdicts.py" "$RESULTS" ${ROW863_LAG_MAX:+--lag-max "$ROW863_LAG_MAX"} | tee "$RESULTS/verdicts.txt"
