#!/bin/bash
# usage: run-app.sh <case> <x-dir> <binary relative path> <kwin-size> -- <app args>   (env: INPUT=script run (as bash) once the window is up, SHOTS=n)
name=$1; xd=$2; bin=$3; size=${4:-1280x800}; shift 4; [ "${1:-}" = "--" ] && shift
ev=/o/evidence/$name; mkdir -p $ev
export HOME=/o/home-$xd XDG_CONFIG_HOME=/o/home-$xd/.config XDG_DATA_HOME=/o/home-$xd/.local/share XDG_CACHE_HOME=/o/home-$xd/.cache XDG_RUNTIME_DIR=/tmp/rt-$$
mkdir -p $XDG_RUNTIME_DIR $HOME; chmod 700 $XDG_RUNTIME_DIR
export LANG=C.UTF-8 LC_ALL=C.UTF-8
export LD_LIBRARY_PATH=${APPLD:-}
export XDG_DATA_DIRS=/o/$xd/usr/share:/o/appdata:/usr/share
export LD_PRELOAD=${SHIM:-/o/tests/gl-shim.so}
export GEOM_FILE=$ev/geom.txt FREEZE_AT=${FREEZE_AT:-0} FREEZE_SECONDS=${FREEZE_SECONDS:-12}
rm -f $GEOM_FILE
exec dbus-run-session -- bash -c '
KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --xwayland --socket=kbwl --width '${size%x*}' --height '${size#*x}' > '$ev'/kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/kbwl && break; sleep .25; done
sleep 1
export QT_QPA_PLATFORM=xcb; unset WAYLAND_DISPLAY; export DISPLAY=:0
${CLIENT_SOFT:+env LIBGL_ALWAYS_SOFTWARE=1} /o/'$xd'/'$bin' '"$*"' > '$ev'/app.log 2>&1 &
ap=$!
sleep ${START_WAIT:-12}
if [ -n "'"${INPUT:-}"'" ]; then bash '"${INPUT:-/dev/null}"' > '$ev'/input.log 2>&1; fi
for i in $(seq 1 120); do test -s '$GEOM_FILE' && break; [ -z "'"${FREEZE_AT}"'" ] || [ "'"${FREEZE_AT}"'" = 0 ] && break; sleep .5; done
sleep ${SETTLE:-2}
/o/tests/capture screen '$ev'/screen.png > '$ev'/capture.log 2>&1
/o/tests/capture window '$ev'/window.png >> '$ev'/capture.log 2>&1
kill $ap 2>/dev/null
wait $ap; echo "app_rc=$?" >> '$ev'/app.log
kill $kp; wait $kp 2>/dev/null
exit 0
'
