#!/bin/bash
# In the container. One proof run: headless Stereo KWin, the patched monado-service with the
# simulated headset and the peek window (XRT_WINDOW_PEEK=both), eyes-client, captures.
# env: NAME, PEEK (both|display|left|right), SDLVD (x11|wayland), BUILD
ev=/lane/work/evidence/${STEP:-step1}/$NAME
mkdir -p $ev
export HOME=/tmp/h LANG=C.UTF-8 LC_ALL=C.UTF-8 XDG_RUNTIME_DIR=/tmp/rt XDG_CONFIG_HOME=/tmp/h/.config XDG_DATA_HOME=/tmp/h/.local/share
rm -rf /tmp/h /tmp/rt; mkdir -p $HOME $XDG_RUNTIME_DIR $XDG_DATA_HOME; chmod 700 $XDG_RUNTIME_DIR
export ev PEEK SDLVD BUILD SERVICE RUNTIME_JSON
exec dbus-run-session -- bash -c '
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
kwin_wayland --virtual --xwayland --socket=sub --width 1600 --height 900 > $ev/kwin.log 2>&1 &
kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/sub && break; sleep .25; done
sleep 2
export WAYLAND_DISPLAY=sub DISPLAY=:0
# The main compositor window is the Play candidate: a Wayland (xdg) window with both eyes.
# Monado and the client stay on lavapipe; only KWin may use a GPU for GL.
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.json
export XRT_COMPOSITOR_FORCE_WAYLAND=${MAINWIN_WL:-1} XRT_COMPOSITOR_LOG=debug SIMULATED_ENABLE=1 XRT_NO_STDIN=1
export SDL_VIDEODRIVER=$SDLVD XRT_COMPOSITOR_SCALE_PERCENTAGE=100
[ "$PEEK" != none ] && export XRT_WINDOW_PEEK=$PEEK
export XR_RUNTIME_JSON=${RUNTIME_JSON:-$BUILD/openxr_monado-dev.json}
export WAYLAND_DEBUG=client
${SERVICE:-$BUILD/src/xrt/targets/service/monado-service} > $ev/monado.raw 2>&1 &
mp=$!
sleep 4
unset WAYLAND_DEBUG
export QT_QPA_PLATFORM=wayland
cap() { for t in 1 2 3 4 5 6; do capture screen $1 > $2 2>&1 && return 0; sleep 1; done; return 1; }
cap $ev/before.png $ev/capture-before.log
$BUILD/eyes-client 400 > $ev/client.log 2>&1 &
cp=$!
sleep 5
cap $ev/cap1.png $ev/capture1.log
sleep 1
cap $ev/cap2.png $ev/capture2.log
wait $cp; echo client_rc=$? >> $ev/client.log
sleep 1
kill $mp 2>/dev/null; sleep 1; kill $kp 2>/dev/null; wait 2>/dev/null
grep -E "kde_stereo_content|set_content|stereo|Peek|peek|Creating|Using|window" $ev/monado.raw | grep -vE "wl_display|wl_registry\.global\(" | head -60 > $ev/monado-stereo.log
exit 0
'
