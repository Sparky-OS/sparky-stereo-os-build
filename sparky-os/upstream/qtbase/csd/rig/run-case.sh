#!/bin/bash
# Inside the run image. usage: run-case.sh <case> <client command...>
# Starts a headless KWin (--virtual --xwayland), runs the client (PLAT=wayland|xcb), captures the
# active window and the screen through KWin's ScreenShot2, and writes the analysis.
case_=$1; shift
ev=/ev
if [ "$(id -u)" = 0 ]; then
  if [ -d /stage/usr ]; then
    cp -a /stage/usr/. /usr/ && ldconfig
    echo "staged Mesa installed: $(ls /usr/lib/x86_64-linux-gnu/libgallium-*.so | tr '\n' ' ')" > $ev/stage.log
  fi
  exec setpriv --reuid=${RUN_UID:-1000} --regid=${RUN_GID:-1000} --groups=125 --inh-caps=-all "$0" "$case_" "$@"
fi
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/rt-$$ XDG_CONFIG_HOME=/tmp/home/.config XDG_DATA_HOME=/tmp/home/.local/share XDG_CACHE_HOME=/tmp/home/.cache
mkdir -p $HOME $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export LANG=C.UTF-8 LC_ALL=C.UTF-8 XDG_DATA_DIRS=/rig/appdata:/usr/share QT_WAYLAND_DISABLE_WINDOWDECORATION=1
[ -n "${CSD:-}" ] && unset QT_WAYLAND_DISABLE_WINDOWDECORATION
# NODECO=1: KWin loads no decoration plugin (the fixed-size X11 tests assume no decoration minimum size)
if [ -n "${NODECO:-}" ]; then mkdir -p $XDG_CONFIG_HOME; printf '[org.kde.kdecoration2]\nNoPlugin=true\n' > $XDG_CONFIG_HOME/kwinrc; fi
export SIZE=${SIZE:-1280x800} WAIT=${WAIT:-5} PLAT=${PLAT:-wayland}
export CLIENT="$*"
{ echo "case=$case_ plat=$PLAT soft=${SOFT:-0} shim=${SHIM:-} myqt=${MYQT:-} size=$SIZE wait=$WAIT"; echo "client=$CLIENT"; echo "client_env=${CLIENT_ENV:-}";
  dpkg-query -W kwin-wayland xwayland libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-libgallium 2>/dev/null; cat $ev/stage.log 2>/dev/null; } > $ev/case.txt
# test aids compiled in the container (small C programs)
mkdir -p /tmp/bin
if [ -n "${SHIM:-}" ]; then
  gcc -shared -fPIC -O1 -o /tmp/bin/finish-shim.so /rig/finish-shim.c -ldl || exit 9
fi
exec dbus-run-session -- bash -c '
kwin_wayland --virtual --xwayland --socket=fbwl --width ${SIZE%x*} --height ${SIZE#*x} > '$ev'/kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/fbwl && break; sleep .25; done
sleep 1.5
export WAYLAND_DISPLAY=fbwl DISPLAY=:0
if [ "$PLAT" = xcb ]; then export QT_QPA_PLATFORM=xcb; else export QT_QPA_PLATFORM=wayland; fi
if [ -n "${MYQT:-}" ]; then export LD_LIBRARY_PATH=/qtpatched/lib QT_PLUGIN_PATH=/qtpatched/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins; fi
cenv=()
[ -n "${SOFT:-}" ] && cenv+=(LIBGL_ALWAYS_SOFTWARE=1)
[ -n "${SHIM:-}" ] && cenv+=(LD_PRELOAD=/tmp/bin/finish-shim.so)
[ -n "${CLIENT_ENV:-}" ] && cenv+=($CLIENT_ENV)
if [ "$PLAT" = xcb ]; then unset WAYLAND_DISPLAY; fi
env "${cenv[@]}" $CLIENT > '$ev'/app.log 2>&1 &
ap=$!
sleep $WAIT
if [ "$PLAT" = xcb ]; then xwininfo -root -tree > '$ev'/xtree.txt 2>&1; for w in $(xwininfo -root -tree | grep -v -E "^\s+0x[0-9a-f]+ \(has no name\)" | grep -o -E "^\s+0x[0-9a-f]+" | head -40); do xprop -id $w 2>/dev/null | grep -q STEREO_CONTENT && { echo "== $w"; xwininfo -id $w | grep -E "Width|Height|geometry"; xprop -id $w | grep -E "STEREO|WM_CLASS|_NET_WM_NAME"; }; done > '$ev'/xwin.txt 2>&1; fi
capture screen '$ev'/screen.png > '$ev'/capture.log 2>&1
capture window '$ev'/window.png >> '$ev'/capture.log 2>&1
python3 /rig/analyze.py '$ev'/window.png > '$ev'/analysis.txt 2>&1
kill -0 $ap 2>/dev/null && echo "client alive after capture" >> '$ev'/capture.log
kill $ap 2>/dev/null; wait $ap; echo "app_rc=$?" >> '$ev'/app.log
kill $kp; wait $kp 2>/dev/null
exit 0
'
