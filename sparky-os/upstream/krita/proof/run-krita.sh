#!/bin/sh
# usage: run-krita.sh <outbase> <prefix-name> <file>   env: PLAT=wayland|xcb, WAIT, KENV (extra env assignments, space separated)
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; export HOME=/w/khome; mkdir -p $HOME/.config
out=$1; P=$2; file=$3
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --xwayland --socket=sub --width ${SW:-1280} --height ${SH:-800} >/tmp/kwin.log 2>&1 &
sleep 4
export WAYLAND_DISPLAY=sub DISPLAY=:0
rm -f $HOME/.config/kritadisplayrc
[ -n "$KRC" ] && printf '%s\n' "$KRC" > $HOME/.config/kritadisplayrc
export RB_OUT=$out LD_PRELOAD="/w/t/rbshim.so ${SPY:+/w/t/eglspy.so}"
export LD_LIBRARY_PATH=/w/prefix/$P/lib/x86_64-linux-gnu XDG_DATA_DIRS=/w/prefix/$P/share:/usr/share ${PLAT:+QT_QPA_PLATFORM=$PLAT} QML2_IMPORT_PATH=/w/prefix/$P/lib/x86_64-linux-gnu/qml QT_LOGGING_RULES="${QLR:-krita.opengl=true}"
env $KENV /w/prefix/$P/bin/krita "$file" >$out.client.log 2>&1 &
cpid=$!
sleep ${WAIT:-60}
touch /tmp/rb.trigger
echo "trigger set"
id=$(dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript string:/w/t/nudge.js string:nudge 2>/dev/null | awk '/int32/{print $2}')
echo "script id=$id"; dbus-send --session --dest=org.kde.KWin /Scripting/Script$id org.kde.kwin.Script.run; sleep 3
QT_QPA_PLATFORM=wayland QT_CAPTURE_SCREEN=1 QT_CAPTURE_PNG=$out.screen.png /p/qt-capture "" red,blue nolabel >$out.capture.txt 2>&1
sleep 1
kill $cpid 2>/dev/null; sleep 2; pkill kwin_wayland; sleep 1; cp /tmp/kwin.log $out.kwin.log
ls $out.0.txt >/dev/null 2>&1 && python3 /w/t/analyze.py $out 2>&1 | tee $out.result.txt || echo "no dump"
