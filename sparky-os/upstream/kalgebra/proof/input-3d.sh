export WAYLAND_DISPLAY=kbwl
F=/o/tests/fakeinput
$F move 600 400 sleep 300 click sleep 500 keydown 0xffe9 keydown 0x33 keyup 0x33 keyup 0xffe9 sleep 2500
