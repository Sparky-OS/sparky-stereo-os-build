#!/bin/sh
# usage: session_multi.sh PLATFORM PATH PROG K  -- one KWin session, K fresh clients in turn
PLATFORM=$1; PATHMODE=$2; PROG=$3; K=${4:-5}
export XDG_RUNTIME_DIR=/tmp/xdg-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export HOME=/tmp/home-$$; mkdir -p $HOME
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export PLATFORM PATHMODE PROG K
exec dbus-run-session -- kwin_wayland --virtual --xwayland --socket=w --width 1280 --height 800 --no-global-shortcuts --exit-with-session /rig/inner_multi.sh
