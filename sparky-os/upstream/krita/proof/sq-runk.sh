#!/bin/bash
# Krita variant of run.sh: env PREFIX (stereo|deb), KRC
export HOME=/w/khome-fresh LANG=C.UTF-8
mkdir -p $HOME/.config; rm -f $HOME/.config/kritadisplayrc; [ -n "$KRC" ] && printf '%s\n' "$KRC" > $HOME/.config/kritadisplayrc
P=${PREFIX:-stereo}
export LD_LIBRARY_PATH=/w/prefix/$P/lib/x86_64-linux-gnu XDG_DATA_DIRS=/w/prefix/$P/share:/usr/share QML2_IMPORT_PATH=/w/prefix/$P/lib/x86_64-linux-gnu/qml
PROG=/w/prefix/$P/bin/krita PROGARGS="${KARGS:-} /w/t/pair-sbs.png" GREP=krita exec /w/t/sq/run.sh "$@"
