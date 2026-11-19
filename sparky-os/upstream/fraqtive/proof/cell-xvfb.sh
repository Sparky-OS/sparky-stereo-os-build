#!/bin/sh
out=$1; shift
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/xdg; mkdir -p $HOME $XDG_RUNTIME_DIR /tmp/fb /tmp/.X11-unix; chmod 700 $XDG_RUNTIME_DIR
for kv in "$@"; do export "$kv"; done
Xvfb :5 -screen 0 1280x800x24 +extension GLX -fbdir /tmp/fb > $out.xvfb.log 2>&1 &
xp=$!; sleep 2
export DISPLAY=:5 QT_QPA_PLATFORM=xcb
glxinfo -B > $out.glxinfo.txt 2>&1
${FQ:-fraqtive} > $out.app.log 2>&1 &
ap=$!; sleep 6
xdotool mousemove 628 529 click 1; sleep 3
cp /tmp/fb/Xvfb_screen0 /tmp/s0.xwd; python3 /w/xwd2png.py /tmp/s0.xwd $out-2d.png
xdotool mousemove ${C3X:-573} 30 click 1; sleep 8; cp /tmp/fb/Xvfb_screen0 /tmp/s2.xwd; python3 /w/xwd2png.py /tmp/s2.xwd $out-3d-8s.png; sleep 25
cp /tmp/fb/Xvfb_screen0 /tmp/s1.xwd; python3 /w/xwd2png.py /tmp/s1.xwd $out-3d.png
kill $ap $xp 2>/dev/null
