#!/bin/bash
# in the container: native Wayland (or xcb with PLAT=xcb) under headless KWin; env: NAME CMD (program + args) WAIT SW SH INPUT (fakeinput args, run after WAIT) SHIM (LD_PRELOAD) SOFT=1 PLAT QT_ENV
out=/ev/${NAME:?}; mkdir -p $out
export HOME=/tmp/h LANG=C.UTF-8 LC_ALL=C.UTF-8 XDG_RUNTIME_DIR=/tmp/rt-$$ XDG_CONFIG_HOME=/tmp/h/.config
rm -rf /tmp/h; mkdir -p $HOME $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
[ -n "$PRE" ] && bash -c "$PRE"
exec dbus-run-session -- bash -c '
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --xwayland --socket=sub --width '${SW:-1280}' --height '${SH:-800}' > '$out'/kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/sub && break; sleep .25; done
sleep 2
export WAYLAND_DISPLAY=sub
if [ "'${PLAT:-wayland}'" = xcb ]; then unset WAYLAND_DISPLAY; export DISPLAY=:0 QT_QPA_PLATFORM=xcb; else export QT_QPA_PLATFORM=wayland WAYLAND_DEBUG=client; fi
[ -n "'$SOFT'" ] && export LIBGL_ALWAYS_SOFTWARE=1
[ -n "'$MYQT'" ] && export LD_LIBRARY_PATH=/qtbuild/lib:$LD_LIBRARY_PATH QT_PLUGIN_PATH=/qtbuild/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins
[ -n "'"$EXTRA_ENV"'" ] && export '"$EXTRA_ENV"'
[ -n "'"$SHIM"'" ] && export LD_PRELOAD='"$SHIM"'
export GEOM_FILE='$out'/geom.txt
'"$CMD"' > '$out'/app.raw 2>&1 &
ap=$!
sleep '${WAIT:-20}'
[ -n "'$FREEZE_AT'" ] && for i in $(seq 1 120); do test -s '$out'/geom.txt && break; sleep .5; done
[ -n "'"$INPUT"'" ] && env -u WAYLAND_DEBUG WAYLAND_DISPLAY=sub fakeinput '"$INPUT"' > '$out'/input.log 2>&1
sleep '${SETTLE:-3}'
env -u WAYLAND_DEBUG capture screen '$out'/screen.png > '$out'/capture.txt 2>&1
env -u WAYLAND_DEBUG capture window '$out'/window.png >> '$out'/capture.txt 2>&1
kill -0 $ap 2>/dev/null && echo alive >> '$out'/capture.txt
kill $ap 2>/dev/null; sleep 1; kill $kp; wait $kp 2>/dev/null
grep -E "kde_stereo_content|get_subsurface|place_below|place_above|set_content|rror|create_surface|set_destination|set_position|get_viewport|get_xdg_surface|get_toplevel|configure\(|set_window_geometry|wl_surface#[0-9]+\.(attach|commit)" '$out'/app.raw > '$out'/wl.txt
grep -vE "^\[[0-9:.]+\]" '$out'/app.raw > '$out'/app.log
exit 0
'
