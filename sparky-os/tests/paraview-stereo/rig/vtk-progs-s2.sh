#!/bin/bash
# vtk-progs-s2.sh PREFIX -- the brief's rows for a shared library, on vtk9 +stereo3d2: every edition program that loads vtk9
# starts and draws (F3D first, on both cards; the Plasma theme studio; FreeCAD; the model viewer and F3D +stereo3d5 of row
# 750b's stage when that stage still exists). Images, made FROM sci50f-rig:green-vtk (the edition's vtk9 in stage/), each
# under its tag, kept until the hand-back's clean-up: sci50f-rig:progs3 and sci50f-rig:staged3. Runs PREFIX-prog-*;
# summary runs/PREFIX-prog-summary.txt (prog_analyze.py). The build container, if running, is paused meanwhile.
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
P=${1:?prefix}; V=$(ls -d $S/stage/vtk9-*); B750=/mnt/build/one-separation-programs-750b/stage
have() { docker image inspect "$1" >/dev/null 2>&1; }
have sci50f-rig:progs3 || FROM=sci50f-rig:green-vtk STAGE="$V" PKGS="libvtk9.6 libvtk9.6-qt f3d sparky-stereo-plasma-theme-studio freecad" TAG=progs3 RIG_CPUS=4 rig/make-green.sh > work/make-progs3.log 2>&1
if [ -d $B750/f3d-3.5.0+dfsg-3+stereo3d5 ] && ! have sci50f-rig:staged3; then
  FROM=sci50f-rig:green-vtk STAGE="$V $B750/f3d-3.5.0+dfsg-3+stereo3d5 $B750/sparky-stereo-model-viewer-0.1.2" PKGS="libvtk9.6 libvtk9.6-qt f3d libf3d3 sparky-stereo-model-viewer" TAG=staged3 RIG_CPUS=4 rig/make-green.sh > work/make-staged3.log 2>&1
fi
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- --filter status=running | head -1); [ -n "$b" ] && docker pause "$b" >/dev/null
run() { rig/run-case.sh "$@" > /dev/null; }
E=LANG=en_US.UTF-8
run $P-prog-f3d-green sci50f-rig:progs3 prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E
GPU=nvidia run $P-prog-f3d-green-nv sci50f-rig:progs3 prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E
run $P-prog-themestudio-green sci50f-rig:progs3 prog-case.sh PROG=sparky-stereo-plasma-theme-studio $E
run $P-prog-freecad-green sci50f-rig:progs3 prog-case.sh PROG=freecad "PROG_ARGS=/fixtures/cube.stl" WAIT=45 $E
if have sci50f-rig:staged3; then
  run $P-prog-f3dstaged-green sci50f-rig:staged3 prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E
  run $P-prog-modelviewer-green sci50f-rig:staged3 prog-case.sh PROG=stereo-model-viewer "PROG_ARGS=/fixtures/two.vtk" $E
fi
[ -n "$b" ] && docker unpause "$b" >/dev/null
for d in runs/$P-prog-*/; do d=${d%/}; old=runs/${d#runs/$P-}; if [ -d "$old" ]; then python3 -I rig/prog_analyze.py $d $old; else python3 -I rig/prog_analyze.py $d; fi; done > runs/$P-prog-summary.txt
cat runs/$P-prog-summary.txt
