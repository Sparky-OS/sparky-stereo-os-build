#!/bin/bash
# usage: kub.sh <name> [env...]   Kubrick --stereo (software or GPU), native Wayland, frame frozen by the shim
n=$1; shift
env NAME=$n FREEZE_AT=60 FREEZE_SECONDS=14 WAIT=5 STATIC_ONLY=1 SHIM=/usr/local/lib/kubrick-shim.so CMD="/usr/games/kubrick --stereo" "$@" ./drun.sh
cd ../ev/$n; echo "== $n"; head -2 capture.txt; python3 ../../rig/wlsurf.py app.raw | grep -E "declared|declaration=set|toplevel"
