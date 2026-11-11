#!/bin/sh
# usage: session.sh PLATFORM(wayland|x11) PATH(shim|zink|plain) PROG [seconds]  -- one fresh KWin session
set -u
PLATFORM=$1; PATHMODE=$2; PROG=$3; SECS=${4:-9}
export XDG_RUNTIME_DIR=/tmp/xdg-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export HOME=/tmp/home-$$; mkdir -p $HOME
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export PLATFORM PATHMODE PROG SECS
exec dbus-run-session -- kwin_wayland --virtual --xwayland --socket=w --width 1280 --height 800 --no-global-shortcuts --exit-with-session /rig/inner.sh
