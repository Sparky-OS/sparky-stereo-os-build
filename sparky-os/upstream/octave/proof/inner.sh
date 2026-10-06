#!/bin/bash
# runs as user t inside the container: headless KWin, Octave on Xwayland with the eye dump shim
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; export HOME=/home/t
export LANG=C.UTF-8 LC_ALL=C.UTF-8
OUT=/w/out/$NAME; rm -rf $OUT; mkdir -p $OUT
kwin_wayland --virtual --xwayland --socket=o1 --width 1280 --height 800 > $OUT/kwin.log 2>&1 & kp=$!
for i in $(seq 1 80); do test -S $XDG_RUNTIME_DIR/o1 && break; sleep .25; done; sleep 2
export DISPLAY=:0 QT_QPA_PLATFORM=xcb KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1
[ "$MODE" = software ] && export LIBGL_ALWAYS_SOFTWARE=1
echo "renderer: $(glxinfo -B 2>/dev/null | grep -m1 'OpenGL renderer' | cut -c1-70)"
echo "announce: $(xprop -root _KDE_NET_WM_STEREO_CONTENT_SUPPORTED 2>&1 | head -1)"
export EYEDUMP_DIR=$OUT EYEDUMP_FRAME=${FRAME:-1} EYEDUMP_AFTER=${AFTER:-3} EYEDUMP_UNTIL=${UNTIL:-9} EYEDUMP_FINISH=1
export OCT_STEREO OCT_HOLD=${HOLD:-12} OCT_OUT=$OUT OCT_PRINT
if [ -n "$CMD" ]; then
  LD_PRELOAD="/w/eyedump.so${TRACE:+ /w/trace.so}" timeout 90 $CMD > $OUT/octave.log 2>&1 &
else
  LD_PRELOAD="/w/eyedump.so${TRACE:+ /w/trace.so}" timeout 90 ${OCTAVE:-octave} --no-gui --norc --eval "run('/w/scene.m')" > $OUT/octave.log 2>&1 &
fi
op=$!
sleep ${SHOT_AT:-8}
xwininfo -root -tree > $OUT/tree.log 2>&1
for w in $(grep -o '^ *0x[0-9a-f]* "[^"]*"' $OUT/tree.log | grep -i -E 'figure|octave' | awk '{print $1}'); do
  echo "window $w: $(xwininfo -id $w | awk '/Width|Height/{printf "%s ", $2}') declared: $(xprop -id $w _KDE_NET_WM_STEREO_CONTENT 2>/dev/null | sed 's/.*= //;s/.*not found.*/no/')"
done | tee $OUT/windows.log
wait $op
kill $kp
grep -h "eyedump\|scene-done\|error" $OUT/octave.log | sort | uniq -c | head -8
ls $OUT
