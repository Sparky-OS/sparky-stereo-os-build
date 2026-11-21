#!/bin/bash
# The VTK reproducer on both routes and both cards, image $IMG, run names pv-$P-qb-...; the build container is paused meanwhile.
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=${IMG:-sci50f-rig:1}; P=${P:-red}
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- --filter status=running | head -1); [ -n "$b" ] && docker pause "$b" >/dev/null
for r in 1 2; do rig/run-case.sh qb-$P-wl-amd-$r $IMG qb-case.sh LANG=en_US.UTF-8 >/dev/null; done
GPU=nvidia rig/run-case.sh qb-$P-wl-nv-1 $IMG qb-case.sh LANG=en_US.UTF-8 >/dev/null
rig/run-case.sh qb-$P-x-amd-1 $IMG qb-case.sh QT_QPA_PLATFORM=xcb LANG=en_US.UTF-8 >/dev/null
GPU=nvidia rig/run-case.sh qb-$P-x-nv-1 $IMG qb-case.sh QT_QPA_PLATFORM=xcb LANG=en_US.UTF-8 >/dev/null
[ -n "$b" ] && docker unpause "$b" >/dev/null
for d in runs/qb-$P-*/; do d=${d%/}; echo "$(basename $d) $(cat $d/rc.txt) $(tr '\n' ' ' < $d/qb.out) set_content=$(grep -c set_content $d/wl.txt) capture=$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("width"), d.get("height"))' $d/shot1.json 2>/dev/null)"; done > runs/qb-$P-summary.txt
cat runs/qb-$P-summary.txt
