#!/bin/sh
set -eu
export HOME=/tmp/order223-kwin-home XDG_RUNTIME_DIR=/tmp/order223-kwin-runtime
mkdir -m 700 -p "$XDG_RUNTIME_DIR" "$HOME"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export QT_QPA_PLATFORM=offscreen
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
if [ "$DISPLAY_GPU" = amd ]; then
 export RIG_COMPOSITOR_RENDER_NODE=${COMPOSITOR_RENDER_NODE:-/dev/dri/renderD128}
 export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
else
 export RIG_COMPOSITOR_RENDER_NODE=${COMPOSITOR_RENDER_NODE:-/dev/dri/renderD129}
 export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
fi
export LD_PRELOAD=/w/compositor-device.so
exec dbus-run-session -- sh -c '
 kwin_wayland --virtual --socket=order223-route --width 1920 --height 1080 --output-count ${OUTPUT_COUNT:-2} > /w/logs/$SCENARIO-kwin.log 2>&1 &
 compositor=$!
 trap "kill $compositor; wait $compositor || true" EXIT
 for i in $(seq 1 100); do [ ! -S "$XDG_RUNTIME_DIR/order223-route" ] || break; sleep .1; done
 test -S "$XDG_RUNTIME_DIR/order223-route"
 unset LD_PRELOAD RIG_COMPOSITOR_RENDER_NODE __EGL_VENDOR_LIBRARY_FILENAMES QT_QPA_PLATFORM
 export WAYLAND_DISPLAY=order223-route
 query=/w/route-build/media-gpu-route-query
 [ "${ROUTE_INSTALLED:-0}" != 1 ] || query=/usr/bin/media-gpu-route-query
 "$query" > /w/logs/$SCENARIO-route.log
 /usr/lib/qt6/bin/qdbus org.kde.KWin /KWin org.kde.KWin.supportInformation > /w/logs/$SCENARIO-support.log
 if [ -n "${CLIENT_SCRIPT:-}" ]; then python3 /kit/$CLIENT_SCRIPT.py; fi
'
