#!/bin/bash
# usage: run-kubrick.sh <case-name> <patched|debian> <kwin-size> -- <kubrick args>
# runs inside the kdesci-kubrick container as the invoking user (cpus capped by docker)
name=$1; flavour=$2; size=${3:-1280x800}; shift 3; [ "${1:-}" = "--" ] && shift
ev=/o/evidence/$name; mkdir -p $ev
export HOME=/o/home XDG_CONFIG_HOME=/o/home/.config XDG_DATA_HOME=/o/home/.local/share XDG_CACHE_HOME=/o/home/.cache XDG_RUNTIME_DIR=/tmp/rt-$$
mkdir -p $XDG_RUNTIME_DIR $HOME; chmod 700 $XDG_RUNTIME_DIR
rm -rf $HOME/.config/kubrickrc $HOME/.local/share/kubrick
export LANG=C.UTF-8 LC_ALL=C.UTF-8
x=/o/x-$flavour
export XDG_DATA_DIRS=$x/usr/share:/o/appdata:/usr/share
if [ -n "${MYQT:-}" ]; then
  export LD_LIBRARY_PATH=/o/qtpatched/lib QT_PLUGIN_PATH=/o/qtpatched/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins
fi
export LD_PRELOAD=/o/tests/kubrick-shim.so
export GEOM_FILE=$ev/geom.txt FREEZE_AT=${FREEZE_AT:-120} FREEZE_SECONDS=${FREEZE_SECONDS:-12}
export QT_QPA_PLATFORM=wayland
rm -f $GEOM_FILE
exec dbus-run-session -- bash -c '
kwin_wayland --virtual --xwayland --socket=kbwl --width '${size%x*}' --height '${size#*x}' > '$ev'/kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/kbwl && break; sleep .25; done
sleep 1
if [ "'${PLAT:-wayland}'" = xcb ]; then export QT_QPA_PLATFORM=xcb; unset WAYLAND_DISPLAY; export DISPLAY=:0; else export WAYLAND_DISPLAY=kbwl; fi
${CLIENT_SOFT:+env LIBGL_ALWAYS_SOFTWARE=1} '$x'/usr/games/kubrick '"$*"' > '$ev'/app.log 2>&1 &
ap=$!
for i in $(seq 1 120); do test -s '$GEOM_FILE' && break; sleep .5; [ -n "'${NOFREEZE:-}'" ] && [ $i -gt 14 ] && break; done
sleep 1
/o/tests/capture screen '$ev'/screen.png > '$ev'/capture.log 2>&1
/o/tests/capture window '$ev'/window.png >> '$ev'/capture.log 2>&1
kill $ap 2>/dev/null
wait $ap; echo "app_rc=$?" >> '$ev'/app.log
kill $kp; wait $kp 2>/dev/null
exit 0
'
