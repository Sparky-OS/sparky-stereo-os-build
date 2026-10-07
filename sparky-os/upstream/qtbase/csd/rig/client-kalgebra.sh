#!/bin/bash
# KAlgebra --stereo on Wayland, the 3D Graph tab opened with Alt+3 through KWin's fake input (a test aid)
kalgebra "$@" &
kp=$!
sleep ${KA_START:-8}
/usr/local/bin/fakeinput move 600 400 sleep 300 click sleep 500 keydown 0xffe9 keydown 0x33 keyup 0x33 keyup 0xffe9 sleep 2500
wait $kp
