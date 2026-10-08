#!/bin/bash
# usage: ka.sh <name> [env...]   KAlgebra --stereo, 3D tab opened with Alt+3, native Wayland
n=$1; shift
env NAME=$n WAIT=14 SHIM=/usr/local/lib/gl-shim.so GEOM_EVERY=1 INPUT="move 600 400 sleep 300 click sleep 500 keydown 0xffe9 keydown 0x33 keyup 0x33 keyup 0xffe9 sleep 2500" CMD="/usr/bin/kalgebra --stereo" "$@" ./drun.sh
cd ../ev/$n; echo "== $n"; head -2 capture.txt; python3 ../../rig/wlsurf.py app.raw | grep -E "declared|declaration=set|toplevel"
