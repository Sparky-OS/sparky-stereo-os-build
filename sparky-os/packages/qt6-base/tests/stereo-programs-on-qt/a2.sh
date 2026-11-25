#!/bin/bash
# a2.sh RESULTS PUB_IMAGE Q24_IMAGE FILMS -- row 863 part A2: VLC Stereo (a Qt 5 program) playing a marked 3D film
# (FILMS/x264-fsbs.mp4: full side by side with the frame packing SEI, made by VLC's own tests/mkclips2.py) in its main
# window, on the published set and on the image with the staged Qt, one fresh session each on the AMD card. The probe,
# built against Qt 5 (PROBE_LIB=r863-probe-qt5.so), watches VLC's VideoWidget and drives the steps: start, grow,
# shrink, the playlist shown and hidden (its View menu action), full screen and back (VLC's f key). analyze-prog.py
# then reads the pair with VLC's own check (check-embedded.py's rule: in the video box the left eye red and the right
# eye blue, the green and yellow markers at its bottom corners, the eyes the same outside it) and the wire log as
# lag.py reads it; maps.txt shows which Qt the process loaded.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
R=$1 PUB=$2 Q24=$3 FILMS=$4
mkdir -p "$R"
STEPS=${A2_STEPS:-grow,shrink,actionx:Playlist,actionx:Playlist,key:f,key:f}
for v in pub q24; do
	img=$PUB; [ $v = q24 ] && img=$Q24
	FILES=$FILMS bash "$HERE/run-prog.sh" "vlc-$v" "$img" "$R" PROBE_LIB=r863-probe-qt5.so R863_WATCH=VideoWidget \
		"PROG=/usr/bin/vlc-stereo --no-qt-privacy-ask --no-qt-video-autoresize --loop --no-audio --no-video-title-show /files/x264-fsbs.mp4" \
		"R863_STEPS=$STEPS" R863_START=10000 R863_WAIT=2500 R863_CAPTURE_MS=2500 R863_QUIT=1 CASE_TIMEOUT=150 > /dev/null
done
python3 -I "$HERE/analyze-prog.py" --measure vlc "$R/vlc-pub" > "$R/vlc-pub.json"
python3 -I "$HERE/analyze-prog.py" --measure vlc "$R/vlc-q24" "$R/vlc-pub" > "$R/vlc-q24.json"
echo "== a2 $(date -u +%H:%M:%SZ)"
