#!/bin/sh
# cell.sh QPA OUTPREFIX [extra env as VAR=val ...]: one fresh session, one case
qpa=$1; out=$2; shift 2
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/home
mkdir -p $XDG_RUNTIME_DIR $HOME /tmp/.X11-unix; chmod 1777 /tmp/.X11-unix; chmod 700 $XDG_RUNTIME_DIR
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
for kv in "$@"; do export "$kv"; done
kwin_wayland --virtual --xwayland --socket=sub --width 1280 --height 800 > $out.kwin.log 2>&1 &
kp=$!
i=0; while [ ! -S $XDG_RUNTIME_DIR/sub ] && [ $i -lt 100 ]; do sleep 0.3; i=$((i+1)); done
sleep 3
if [ "$qpa" = xcb ]; then export DISPLAY=:0 QT_QPA_PLATFORM=xcb; unset WAYLAND_DISPLAY; else export WAYLAND_DISPLAY=sub QT_QPA_PLATFORM=wayland-egl; fi
[ "$qpa" = wayland ] && export QT_QPA_PLATFORM=wayland
${FQ:-fraqtive} > $out.app.log 2>&1 &
ap=$!
sleep 8
WAYLAND_DISPLAY=sub /w/bin/fakeinput k:28 > $out.fi0.log 2>&1
sleep 5
python3 /w/skill/capture.py $out-2d.png > $out.cap2d.json 2>&1
WAYLAND_DISPLAY=sub /w/bin/fakeinput k:61 > $out.fi.log 2>&1
sleep 8
python3 /w/skill/capture.py $out-3d.png > $out.cap3d.json 2>&1
kill $ap $kp 2>/dev/null; sleep 1
