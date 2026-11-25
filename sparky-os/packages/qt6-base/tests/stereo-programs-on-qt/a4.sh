#!/bin/bash
# a4.sh RESULTS PUB_IMAGE Q24_IMAGE -- row 863 part A4: Qt's own client-side frame around a plain Qt Widgets window
# (frame-check), resized by the frame's bottom-right corner and then its left edge with fake input, captured after
# every move with the button down and after each release; on the published set and on the staged Qt, one fresh session
# each on the AMD card; then the known bad case (FC_STALE=1: the content's border painted at the paint before's size)
# on the staged Qt. frame-analyze.py says for each capture whether the frame and the content agree.
# PROBE_SO: the r863-probe.so of build-aids.sh, with frame-check beside it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
R=$1 PUB=$2 Q24=$3
mkdir -p "$R"
for v in pub q24; do
	img=$PUB; [ $v = q24 ] && img=$Q24
	CASE_SCRIPT=frame-case.sh bash "$HERE/run-prog.sh" "frame-$v" "$img" "$R" DRAG_STEPS=4 > /dev/null
	python3 -I "$HERE/frame-analyze.py" "$R/frame-$v" > "$R/frame-$v.json"
done
CASE_SCRIPT=frame-case.sh bash "$HERE/run-prog.sh" bad-frame-q24 "$Q24" "$R" DRAG_STEPS=4 FC_STALE=1 > /dev/null
python3 -I "$HERE/frame-analyze.py" "$R/bad-frame-q24" > "$R/bad-frame-q24.json"
echo "== a4 $(date -u +%H:%M:%SZ)"
