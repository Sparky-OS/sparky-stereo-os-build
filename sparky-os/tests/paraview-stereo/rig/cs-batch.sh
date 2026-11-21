#!/bin/bash
# The colour-size warnings: red (Debian's vtk9, no shim), the probe (the state at the query) and green (the drafted rule
# through the shim), on Wayland and xcb, AMD and the RTX 3060. Image $IMG (default sci50f-rig:1, Debian's vtk9).
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=${IMG:-sci50f-rig:1}
run() { rig/run-case.sh "$@" > /dev/null; }
paused=; b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- | head -1)
[ -n "$b" ] && docker pause "$b" >/dev/null && paused=$b
for mode in red probe fix; do
  shim=; [ $mode = red ] || shim=SHIM=$mode
  run cs-$mode-wl-amd $IMG cs-case.sh $shim
  run cs-$mode-x-amd $IMG cs-case.sh $shim QT_QPA_PLATFORM=xcb
  GPU=nvidia run cs-$mode-wl-nv $IMG cs-case.sh $shim
  GPU=nvidia run cs-$mode-x-nv $IMG cs-case.sh $shim QT_QPA_PLATFORM=xcb
done
[ -n "$paused" ] && docker unpause "$paused" >/dev/null
for d in runs/cs-*/; do d=${d%/}; echo "$(basename $d) $(cat $d/rc.txt 2>/dev/null) $(tr '\n' ' ' < $d/cs.out 2>/dev/null) | $(grep -h -m1 'colour-size-shim' $d/cs.err 2>/dev/null | cut -c1-200)"; done > runs/cs-summary.txt
echo "cs done"
