#!/bin/sh
set -eu
export XDG_RUNTIME_DIR=/tmp/order223-runtime
mkdir -m 700 -p "$XDG_RUNTIME_DIR"
export WAYLAND_DISPLAY=order223 QT_QPA_PLATFORM=wayland
unset DISPLAY XAUTHORITY
export LD_PRELOAD=/w/decoder-trace.so
exec timeout 60 weston --backend=headless --renderer=gl --width=800 --height=600 --shell=kiosk --no-config --socket=order223 --log=/w/logs/weston-final-$GPU.log -- sh /kit/tests/vlc-qt-cases.sh
