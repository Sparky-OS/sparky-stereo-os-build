#!/bin/bash
# usage: kz.sh <name> [env...]   Kalzium --stereo -m chain.xyz (the molecule editor), native Wayland; KZBIN selects the binary
n=$1; shift
env NAME=$n WAIT=16 GEOM_EVERY=1 SHIM=/usr/local/lib/gl-shim.so CMD="${KZBIN:-/usr/bin/kalzium} --stereo -m /w/chain.xyz" "$@" ./drun.sh
cd ../ev/$n; echo "== $n"; head -2 capture.txt; python3 ../../rig/wlsurf.py app.raw | grep -E "declared|declaration=set|toplevel"
