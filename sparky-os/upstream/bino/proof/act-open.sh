#!/bin/bash
# File > Open with Ctrl+O, type a path, Return: makes Bino save its "Directory" setting (KWin fake input)
export WAYLAND_DISPLAY=bnwl
F=/proof/fakeinput
$F move 600 400 sleep 300 click sleep 300 keydown 0xffe3 keydown 0x6f keyup 0x6f keyup 0xffe3 sleep 2000 type /clips/sbs-R.mkv sleep 500 keydown 0xff0d keyup 0xff0d sleep 3000
