#!/bin/sh
set -eu
export HOME=${HOME:-/tmp/order223-home}
mkdir -p "$HOME"
export XDG_RUNTIME_DIR=/tmp/order223-route
mkdir -m 700 -p "$XDG_RUNTIME_DIR"
unset DISPLAY XAUTHORITY WAYLAND_DISPLAY
if [ "$DISPLAY_GPU" = amd ]; then
 export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
else
 export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
fi
exec weston --backend=headless --renderer=gl --width=1920 --height=1080 --refresh-rate=60000 --shell=kiosk --no-config --socket=order223-route --log=/w/logs/$SCENARIO-weston.log -- sh /kit/${CLIENT_SCRIPT:-baseline-clients}.sh
