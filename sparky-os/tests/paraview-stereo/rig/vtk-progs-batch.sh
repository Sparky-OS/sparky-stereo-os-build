#!/bin/bash
# The brief's rows for a shared library: every edition program that loads vtk9 starts and draws on the edition's vtk9, F3D
# first, each beside the same program on Debian's vtk9. Images (made here when missing, one CPU):
#   sci50f-rig:progs-red    sci50f-rig:1 + f3d +stereo3d3 (published), sparky-stereo-plasma-theme-studio 0.3.0 (published), freecad
#   sci50f-rig:progs-green  sci50f-rig:green-vtk + the same
#   sci50f-rig:staged-red   sci50f-rig:1 + f3d and libf3d3 +stereo3d5 and sparky-stereo-model-viewer 0.1.2 (row 750b's stage)
#   sci50f-rig:staged-green sci50f-rig:green-vtk + the same
# Runs prog-<program>-<red|green>[-nv]; the vtk9 build, if running, is paused meanwhile. Summary: runs/prog-summary.txt.
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
V=$S/stage/vtk9-9.6.2+ds-3+stereo3d1
B750=/mnt/build/one-separation-programs-750b/stage
have() { docker image inspect "$1" >/dev/null 2>&1; }
pub="f3d sparky-stereo-plasma-theme-studio freecad"; stg="f3d libf3d3 sparky-stereo-model-viewer"
have sci50f-rig:progs-red || FROM=sci50f-rig:1 STAGE="" PKGS="$pub" TAG=progs-red RIG_CPUS=1 rig/make-green.sh > work/make-progs-red.log 2>&1
have sci50f-rig:progs-green || FROM=sci50f-rig:green-vtk STAGE="$V" PKGS="libvtk9.6 libvtk9.6-qt $pub" TAG=progs-green RIG_CPUS=1 rig/make-green.sh > work/make-progs-green.log 2>&1
have sci50f-rig:staged-red || FROM=sci50f-rig:1 STAGE="$B750/f3d-3.5.0+dfsg-3+stereo3d5 $B750/sparky-stereo-model-viewer-0.1.2" PKGS="$stg" TAG=staged-red RIG_CPUS=1 rig/make-green.sh > work/make-staged-red.log 2>&1
have sci50f-rig:staged-green || FROM=sci50f-rig:green-vtk STAGE="$V $B750/f3d-3.5.0+dfsg-3+stereo3d5 $B750/sparky-stereo-model-viewer-0.1.2" PKGS="libvtk9.6 libvtk9.6-qt $stg" TAG=staged-green RIG_CPUS=1 rig/make-green.sh > work/make-staged-green.log 2>&1
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- --filter status=running | head -1); [ -n "$b" ] && docker pause "$b" >/dev/null
run() { rig/run-case.sh "$@" > /dev/null; }
E=LANG=en_US.UTF-8
for c in red green; do
  run prog-f3d-$c sci50f-rig:progs-$c prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E
  GPU=nvidia run prog-f3d-$c-nv sci50f-rig:progs-$c prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E
  run prog-f3dstaged-$c sci50f-rig:staged-$c prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E
  run prog-modelviewer-$c sci50f-rig:staged-$c prog-case.sh PROG=stereo-model-viewer "PROG_ARGS=/fixtures/two.vtk" $E
  run prog-themestudio-$c sci50f-rig:progs-$c prog-case.sh PROG=sparky-stereo-plasma-theme-studio $E
  run prog-freecad-$c sci50f-rig:progs-$c prog-case.sh PROG=freecad "PROG_ARGS=/fixtures/cube.stl" WAIT=45 $E
done
[ -n "$b" ] && docker unpause "$b" >/dev/null
for d in runs/prog-*-green*/; do d=${d%/}; red=${d/-green/-red}; python3 -I rig/prog_analyze.py $d $red; done > runs/prog-summary.txt
for d in runs/prog-*-red*/; do d=${d%/}; python3 -I rig/prog_analyze.py $d; done >> runs/prog-summary.txt
cat runs/prog-summary.txt
