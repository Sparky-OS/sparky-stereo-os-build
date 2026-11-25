#!/bin/bash
# a5.sh RESULTS PUB_IMAGE Q24_IMAGE -- row 863 part A5: the installer's slideshow in a window of its own, without the
# installer: Qt's qml tool runs slideshow-r863.qml, which loads the edition's branding (show.qml, StereoSlide.qml with
# the stereo layer's StereoPicture) and Calamares' own calamares.slideshow module, both unpacked from their packages in
# /opt/r863 of the image (Calamares itself is not installed). The wrapper logs the picture's place and runs the steps;
# on the published set and on the staged Qt, one fresh session each on the AMD card; analyze-prog.py with lag.py.
# --transparent: the window asks for an alpha channel when it is made. The stereo layer's StereoPicture needs one, and
# asks for it only for a window not made yet (PictureItem::prepareWindow); in a window made before the slideshow loads
# it stays flat, with nothing in stereoFailure (found on this row's first run). OUTPUT_MODE=3d: StereoPicture draws two
# eyes only on a screen that shows them (its showsTwoEyes(): a stereo or an anaglyph output); the rig's plain virtual
# output is a 2D screen, where one view is the designed picture (the second run).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
R=$1 PUB=$2 Q24=$3
B=/opt/r863/usr/share/calamares
mkdir -p "$R"
for v in pub q24; do
	img=$PUB; [ $v = q24 ] && img=$Q24
	bash "$HERE/run-prog.sh" "slideshow-$v" "$img" "$R" \
		"PROG=${QML_TOOL:-/usr/lib/qt6/bin/qml} --transparent -I $B/qml /tests/slideshow-r863.qml -- $B/branding/sparky-stereo/show.qml /out" \
		"PROGENV=QSG_RENDER_LOOP=basic QML_XHR_ALLOW_FILE_WRITE=1 QML_XHR_ALLOW_FILE_READ=1 QT_MESSAGE_PATTERN=%{message}" \
		OUTPUT_MODE=3d CASE_TIMEOUT=120 > /dev/null
done
python3 -I "$HERE/analyze-prog.py" "$R/slideshow-pub" > "$R/slideshow-pub.json"
python3 -I "$HERE/analyze-prog.py" "$R/slideshow-q24" "$R/slideshow-pub" > "$R/slideshow-q24.json"
echo "== a5 $(date -u +%H:%M:%SZ)"
