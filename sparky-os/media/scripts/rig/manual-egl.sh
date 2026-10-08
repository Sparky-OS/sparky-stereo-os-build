#!/bin/sh
# manual: headless KWin + mpv with the given args, print mpv's exit status
export XDG_RUNTIME_DIR=/tmp/rt; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export HOME=/tmp/home; mkdir -p $HOME
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 kwin_wayland --virtual --xwayland --socket=sub --width 1280 --height 800 > /tmp/kwin.log 2>&1 &
for i in $(seq 40); do [ -e $XDG_RUNTIME_DIR/sub ] && break; sleep 0.25; done; sleep 1.5
WAYLAND_DISPLAY=sub timeout 20 "$@" > /tmp/mpv.out 2>&1
echo "mpv exit status: $?"
grep -vE "Registered interface|^\[cplayer\] Setting option|^\[ffmpeg" /tmp/mpv.out | tail -${TAILN:-40} | cut -c1-220
