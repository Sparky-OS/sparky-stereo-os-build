#!/bin/bash
# drag the picture with the left mouse button (Bino's own view control in surround mode) through KWin's fake input;
# DX / DY in pixels (default 200 / 0). Pointer starts in the left-eye half of the window.
export DISPLAY=:0
read X Y W H < <(xwininfo -name Bino 2>/dev/null | awk '/Absolute upper-left X/{x=$4}/Absolute upper-left Y/{y=$4}/Width:/{w=$2}/Height:/{h=$2}END{print x,y,w,h}')
echo "window at $X,$Y size ${W}x${H}"
cx=$((X + W/4)); cy=$((Y + H/2))
export WAYLAND_DISPLAY=bnwl
/proof/fakeinput move $cx $cy sleep 300 drag $cx $cy $((cx + ${DX:-200})) $((cy + ${DY:-0})) sleep 1000
