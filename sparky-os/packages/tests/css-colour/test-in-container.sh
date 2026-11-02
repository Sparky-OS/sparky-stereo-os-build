#!/bin/bash
# Sparky Stereo OS: builds the two renderers' harnesses against the installed Qt SVG and librsvg and renders the corpus.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Runs inside a fresh debian:testing container; test.sh starts it. /corpus is the test set, /tools this folder, /out the
# results folder, /debs (optional) the candidate .deb files to install over Debian's.
trap 'chown -R 1000:1000 /out' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/out/apt.log 2>&1
apt-get -y install --no-install-recommends g++ pkg-config qt6-base-dev qt6-svg-dev librsvg2-dev libcairo2-dev \
	python3 >>/out/apt.log 2>&1
if [ -d /debs ]; then
	debs=()
	for f in /debs/*.deb; do
		case $f in *-dbgsym_*|*-lc-hr_*|*-doc_*|*-doc-*|*-tests_*|*examples*) ;; *) debs+=("$f") ;; esac
	done
	apt-get -y install --no-install-recommends "${debs[@]}" >>/out/apt.log 2>&1
fi
dpkg-query -W -f '${Package} ${Version}\n' libqt6svg6 qt6-svg-dev librsvg2-2 librsvg2-dev libcairo2 libqt6gui6 > /out/versions.txt
cd /out
g++ -std=c++17 -O1 -fPIC -o qt_render /tools/qt_render.cpp $(pkg-config --cflags --libs Qt6Svg Qt6Gui Qt6Core) 2>/out/build-qt.log
gcc -O1 -o rsvg_render /tools/rsvg_render.c $(pkg-config --cflags --libs librsvg-2.0 cairo glib-2.0) 2>/out/build-rsvg.log
python3 -I /tools/rsvg_cases.py /corpus/cases.json > /out/rsvg-cases.txt
mkdir -p /out/tmp
export LC_ALL=C.UTF-8
QT_QPA_PLATFORM=offscreen ./qt_render /corpus > /out/qt.jsonl 2>/out/qt.stderr
# librsvg says what it does on RSVG_LOG, its log channel
RSVG_LOG=1 RSVG_RENDER_TMP=/out/tmp ./rsvg_render /corpus /out/rsvg-cases.txt > /out/rsvg.jsonl 2>/out/rsvg.stderr
rmdir /out/tmp
rm -f qt_render rsvg_render
python3 -I /tools/compare.py /corpus/cases.json /out/qt.jsonl /out/rsvg.jsonl --out /out/compare > /out/summary.txt
