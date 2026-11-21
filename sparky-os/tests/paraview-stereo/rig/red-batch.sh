#!/bin/bash
# The red rows of step 2: Debian's paraview 6.1.1+dfsg1-3 on Debian's vtk9 9.6.2+ds-3 (image sci50f-rig:1), Crystal Eyes on
# both routes (native Wayland as the session starts it; the GLX child with QT_QPA_PLATFORM=xcb) and both cards, plus the
# mono starts. One fresh container and Stereo KWin session per run. The vtk9 build container, if running, is paused
# meanwhile so this lane stays at four CPUs.
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=${IMG:-sci50f-rig:1}; P=${P:-red}
paused=
if docker ps --format '{{.Names}}' --filter name=sci50f-build- | grep -q .; then
  b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- | head -1); docker pause "$b" >/dev/null && paused=$b
fi
run() { rig/run-case.sh "$@" > /dev/null; }
L=LANG=en_US.UTF-8
for i in 1 2; do run pv-$P-ce-wl-amd-$i $IMG pv-case.sh "PV_STEREO=Crystal Eyes" $L; done
GPU=nvidia run pv-$P-ce-wl-nv-1 $IMG pv-case.sh "PV_STEREO=Crystal Eyes" $L
run pv-$P-ce-x-amd-1 $IMG pv-case.sh "PV_STEREO=Crystal Eyes" QT_QPA_PLATFORM=xcb $L
GPU=nvidia run pv-$P-ce-x-nv-1 $IMG pv-case.sh "PV_STEREO=Crystal Eyes" QT_QPA_PLATFORM=xcb $L
run pv-$P-mono-wl-amd $IMG pv-case.sh $L
run pv-$P-mono-x-amd $IMG pv-case.sh QT_QPA_PLATFORM=xcb $L
[ -n "$paused" ] && docker unpause "$paused" >/dev/null
for d in runs/pv-$P-*; do echo "$(basename $d) warnings=$(cat $d/drawbuffer-warnings.txt 2>/dev/null) set_content=$(grep -c set_content $d/wl.txt 2>/dev/null) $(python3 -I rig/pv_analyze.py $d | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print("stereo", d["stereo"], "measured", d.get("measured"), "pred", {k: d.get("prediction", {}).get(k) for k in ("near","far")}, "vert", d.get("disparity", {}).get("near_red", {}).get("y0"), d.get("disparity", {}).get("far_blue", {}).get("y0"), "diff_outside", d.get("differing_outside_view"))')"; done > runs/pv-$P-summary.txt
echo done
