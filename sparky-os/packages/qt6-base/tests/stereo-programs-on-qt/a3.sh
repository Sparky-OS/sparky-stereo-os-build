#!/bin/bash
# a3.sh RESULTS PUB_IMAGE Q24_IMAGE FILES -- row 863 part A3: Krita with its "Stereo 3D" canvas (stereo3DCanvas=true in
# kritadisplayrc, as Krita's own proof set it) and a side-by-side document open (FILES/krita-pair.png, 1600x700): the
# canvas is shown through KisStereoCanvasLayer, a child QWindow of the main window (a QtWayland subsurface) that Krita
# moves to the canvas widget's rectangle from a 100 ms timer (patch 0005). The probe watches the canvas widget and reads
# that window (R863_LAYER=1); the steps hide and show every docker, then grow and shrink the window. On the published set
# and on the staged Qt, one fresh session each on the AMD card; analyze-prog.py with lag.py for each.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
R=$1 PUB=$2 Q24=$3 FILES=$4
mkdir -p "$R"
for v in pub q24; do
	img=$PUB; [ $v = q24 ] && img=$Q24
	FILES=$FILES bash "$HERE/run-prog.sh" "krita-$v" "$img" "$R" R863_WATCH=KisOpenGLCanvas2 R863_LAYER=1 \
		'PRESETUP=mkdir -p $XDG_CONFIG_HOME && printf "stereo3DCanvas=true\n" > $XDG_CONFIG_HOME/kritadisplayrc' \
		"PROG=/usr/bin/krita --nosplash /files/krita-pair.png" "R863_STEPS=${A3_STEPS:-dock,dock,grow,shrink}" \
		R863_START=45000 R863_WAIT=2500 R863_CAPTURE_MS=2500 R863_QUIT=1 CASE_TIMEOUT=240 > /dev/null
done
python3 -I "$HERE/analyze-prog.py" "$R/krita-pub" > "$R/krita-pub.json"
python3 -I "$HERE/analyze-prog.py" "$R/krita-q24" "$R/krita-pub" > "$R/krita-q24.json"
echo "== a3 $(date -u +%H:%M:%SZ)"
