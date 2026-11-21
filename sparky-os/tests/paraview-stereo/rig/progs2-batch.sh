#!/bin/bash
# The programs rows vtk-progs-batch.sh could not run: sci50f-rig:progs-green without sparky-stereo-plasma-theme-studio (its
# plasma-workspace chain cannot be installed on today's testing with the published tree: KF6 6.32 against 6.30), then F3D
# (published) on both cards and FreeCAD on the edition's vtk9. The build container, if running, is paused meanwhile.
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
FROM=sci50f-rig:green-vtk STAGE="$S/stage/vtk9-9.6.2+ds-3+stereo3d1" PKGS="libvtk9.6 libvtk9.6-qt f3d freecad" TAG=progs-green RIG_CPUS=1 rig/make-green.sh > work/make-progs-green.log 2>&1 || { tail -5 work/make-progs-green.log; exit 1; }
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- --filter status=running | head -1); [ -n "$b" ] && docker pause "$b" >/dev/null
E=LANG=en_US.UTF-8
rig/run-case.sh prog-f3d-green sci50f-rig:progs-green prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E > /dev/null
GPU=nvidia rig/run-case.sh prog-f3d-green-nv sci50f-rig:progs-green prog-case.sh PROG=f3d "PROG_ARGS=/fixtures/two.vtk" $E > /dev/null
rig/run-case.sh prog-freecad-green sci50f-rig:progs-green prog-case.sh PROG=freecad "PROG_ARGS=/fixtures/cube.stl" WAIT=45 $E > /dev/null
[ -n "$b" ] && docker unpause "$b" >/dev/null
for d in runs/prog-*-green*/; do d=${d%/}; red=${d/-green/-red}; if [ -d "$red" ]; then python3 -I rig/prog_analyze.py $d $red; else python3 -I rig/prog_analyze.py $d; fi; done > runs/prog-summary.txt 2>&1
for d in runs/prog-*-red*/; do d=${d%/}; python3 -I rig/prog_analyze.py $d; done >> runs/prog-summary.txt 2>&1
echo "programs rows 2 done"
