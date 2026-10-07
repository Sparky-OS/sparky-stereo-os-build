#!/bin/bash
# usage: run.sh <out> [env...]  headless KWin + Xwayland, the test app on xcb
out=$1; shift
export XDG_RUNTIME_DIR=/tmp/rt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; export HOME=${HOME:-/tmp/h-$$} LANG=C.UTF-8; mkdir -p $HOME
exec dbus-run-session -- bash -c '
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --xwayland --socket=sub --width 1280 --height 800 > '$out'.kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/sub && break; sleep .25; done; sleep 2
unset WAYLAND_DISPLAY; export DISPLAY=:0 QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1
/w/t/sq/xcbwatch > '$out'.xcb.log 2>&1 &
sleep 1
env '"$*"' ${PROG:-/w/t/sq/sqtest} ${PROGARGS:-} > '$out'.log 2>&1 &
cp=$!
sleep ${WAIT:-12}
/w/t/capture window '$out'.window.png > '$out'.capture.txt 2>&1
for w in $(xwininfo -root -tree | grep -i "${GREP:-sqtest}" | awk "{print \$1}"); do echo "$w $(xwininfo -id $w | grep -E "Width|Height" | tr "\n" " ")" >> '$out'.capture.txt; done
kill $cp; sleep 1; kill $kp
'
