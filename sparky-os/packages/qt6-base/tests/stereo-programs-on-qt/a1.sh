#!/bin/bash
# a1.sh RESULTS PUB_IMAGE Q24_IMAGE -- row 863 part A1: Kubrick, KAlgebra (its 3D graph), Kalzium (its molecule view) and
# Fraqtive (its 3D view), each on the published set and on the image with the staged Qt, the same steps, one fresh
# Stereo KWin session per run on the AMD card; then analyze-prog.py on each with the program's own proof measure, the +24
# run against the published one. Last, lag-selftest.py: the known bad cases of the wire-log measure, on Kubrick's +24 log.
# PROBE_SO: the r863-probe.so that build-aids.sh made, gl-shim.so and kubrick-shim-r863.so beside it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
RIG=$(cd "${R863_UPSTREAM:-$HERE/../../../../upstream}/qtbase/glwidget/rig" && pwd -P)
R=$1 PUB=$2 Q24=$3
mkdir -p "$R"
common=(R863_START=9000 R863_WAIT=2500 R863_QUIT=1 CASE_TIMEOUT=180 GEOM_FILE=/out/geom.txt GEOM_EVERY=1)
declare -A prog steps shim measure
prog[kubrick]="/usr/games/kubrick --stereo";        steps[kubrick]=click,wait,wait,grow,shrink,full,full
shim[kubrick]=kubrick-shim-r863.so;                 measure[kubrick]=kubrick
prog[kalgebra]="/usr/bin/kalgebra --stereo";        steps[kalgebra]=tab:2,grow,shrink,tab:1,tab:2
shim[kalgebra]=gl-shim.so;                          measure[kalgebra]=kalgebra
prog[kalzium]="/usr/bin/kalzium --stereo -m /files/chain.xyz"; steps[kalzium]=grow,shrink,tab:1,tab:0
shim[kalzium]=gl-shim.so;                           measure[kalzium]=kalzium:$RIG/chain.xyz
prog[fraqtive]=/usr/bin/fraqtive;                   steps[fraqtive]="action:3D View,dock,dock,shrink,grow"
shim[fraqtive]=;                                    measure[fraqtive]=fraqtive
one() { # name image program-key steps
	FILES=$RIG bash "$HERE/run-prog.sh" "$1" "$2" "$R" "PROG=${prog[$3]}" "R863_STEPS=$4" "SHIM=${shim[$3]}" DETERMINISTIC=1 \
		"${common[@]}" > /dev/null
}
for p in kubrick kalgebra kalzium fraqtive; do
	one "$p-pub" "$PUB" "$p" "${steps[$p]}"
	one "$p-q24" "$Q24" "$p" "${steps[$p]}"
	python3 -I "$HERE/analyze-prog.py" --measure "${measure[$p]}" "$R/$p-pub" > "$R/$p-pub.json"
	python3 -I "$HERE/analyze-prog.py" --measure "${measure[$p]}" "$R/$p-q24" "$R/$p-pub" > "$R/$p-q24.json"
	echo "== $p $(date -u +%H:%M:%SZ)"
done
# the known bad cases of the wire-log measure: Kubrick's +24 log (Qt changed its frame there) changed three ways
python3 -I "$HERE/lag-selftest.py" "$R/kubrick-q24/stderr.txt" > "$R/lag-selftest.txt" 2>&1; echo "lag-selftest rc=$?" >> "$R/lag-selftest.txt"
echo "== lag self-test $(date -u +%H:%M:%SZ): $(tail -1 "$R/lag-selftest.txt")"
