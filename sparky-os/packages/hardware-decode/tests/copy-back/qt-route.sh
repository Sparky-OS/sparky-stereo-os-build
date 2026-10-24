#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
# Qt Multimedia's automatic decoder choice through libmedia-gpu-route: its
# texture converters import decoded surfaces, so it asks as an importing
# caller and keeps hardware decoding by default. Builds the probe against
# the installed Qt and runs it with no display (offscreen).
# Usage: qt-route.sh OUTDIR FILM WORKDIR
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=$1 film=$2 work=$3
mkdir -p "$out" "$work"
c++ -Wall -Wextra -Werror -fPIC "$here/qt-route-probe.cpp" -o "$work/qt-route-probe" \
    $(pkg-config --cflags --libs Qt6Multimedia Qt6Gui Qt6Core) || exit 1
export QT_QPA_PLATFORM=offscreen QT_LOGGING_RULES='qt.multimedia.ffmpeg.hwaccel.debug=true'
export XDG_CONFIG_DIRS=/nonexistent XDG_CONFIG_HOME=/nonexistent XDG_RUNTIME_DIR=$work
unset MEDIA_GPU_ROUTE_COPY_BACK DISPLAY WAYLAND_DISPLAY
"$work/qt-route-probe" "$film" > "$out/qt-default.log" 2>&1
dpkg-query -W -f='${Package} ${Version}\n' libqt6multimedia6 libmedia-gpu-route0 > "$out/versions.txt"
# The decoder's get_format names the hardware surface it took ("Selected format 44 for hw 3" is VA-API),
# or a software format ("Selected format with no conversion").
chosen=$(grep -m1 -oE 'Selected format.*' "$out/qt-default.log")
if grep -qE 'Selected format [0-9]+ for hw' "$out/qt-default.log" && grep -q '^frames=[1-9]' "$out/qt-default.log"; then
    echo "ok   qt-default: hardware decoding by default ($chosen)"; echo PASSED; exit 0
fi
echo "FAIL qt-default: software decoding by default ($chosen, $(grep -m1 '^frames=' "$out/qt-default.log"))"; echo FAILED; exit 1
