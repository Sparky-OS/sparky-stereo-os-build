#!/bin/bash
# inside the container, as the invoking user. usage: run-bino.sh <case> <bino args...>
ev=/ev
export HOME=/o/home XDG_CONFIG_HOME=/o/home/.config XDG_DATA_HOME=/o/home/.local/share XDG_CACHE_HOME=/o/home/.cache XDG_RUNTIME_DIR=/tmp/rt-$$
mkdir -p $XDG_RUNTIME_DIR $HOME; chmod 700 $XDG_RUNTIME_DIR
[ -n "$KEEP_CFG" ] || rm -rf $HOME/.config/bino* $HOME/.config/Bino* $HOME/.local/share/bino* 2>/dev/null
export LANG=C.UTF-8 LC_ALL=C.UTF-8 XDG_DATA_DIRS=/proof/appdata:/usr/share
export SIZE=${SIZE:-1280x800} WAIT=${WAIT:-8} PLAT=${PLAT:-xcb}
export BINO_ARGS="$*"
exec dbus-run-session -- bash -c '
kwin_wayland --virtual --xwayland --socket=bnwl --width ${SIZE%x*} --height ${SIZE#*x} > '$ev'/kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/bnwl && break; sleep .25; done
sleep 1
if [ "$PLAT" = xcb ]; then export QT_QPA_PLATFORM=xcb; unset WAYLAND_DISPLAY; export DISPLAY=:0
else export QT_QPA_PLATFORM=wayland; export WAYLAND_DISPLAY=bnwl; fi
export QT_LOGGING_RULES="qt.qpa.gl=true;qt.qpa.xcb.glx=true"
env $BINO_ENV bino --log-level ${BINO_LOG:-debug} --log-file '$ev'/bino.log $BINO_ARGS > '$ev'/app.log 2>&1 &
ap=$!
sleep $WAIT
if [ "$PLAT" = xcb ]; then
  xwininfo -root -tree > '$ev'/xtree-1.txt 2>&1
fi
[ -n "$ACT" ] && bash /proof/$ACT '$ev' > '$ev'/act.log 2>&1
capture screen '$ev'/screen.png > '$ev'/capture.log 2>&1
capture window '$ev'/window.png >> '$ev'/capture.log 2>&1
if [ "$PLAT" = xcb ]; then
  xwininfo -root -tree > '$ev'/xtree-2.txt 2>&1
  for w in $(xdotool search --onlyvisible --class bino 2>/dev/null); do echo "== $w"; xwininfo -id $w; xprop -id $w | grep -i -E "STEREO|WM_CLASS|NET_WM_NAME"; done > '$ev'/xwin.txt 2>&1
fi
kill -0 $ap 2>/dev/null && echo "bino alive after capture" >> '$ev'/capture.log
kill $ap 2>/dev/null
wait $ap; echo "app_rc=$?" >> '$ev'/app.log
kill $kp; wait $kp 2>/dev/null
exit 0
'
