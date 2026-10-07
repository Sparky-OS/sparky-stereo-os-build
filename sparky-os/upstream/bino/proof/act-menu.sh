#!/bin/bash
# open the "3D Modes" menu with a click (KWin fake input); the menu is a popup window, read it from screen.png
export DISPLAY=:0
read X Y < <(xwininfo -name Bino 2>/dev/null | awk '/Absolute upper-left X/{x=$4}/Absolute upper-left Y/{y=$4}END{print x,y}')
export WAYLAND_DISPLAY=bnwl
/proof/fakeinput move $((X+185)) $((Y+9)) sleep 300 click sleep 1500
