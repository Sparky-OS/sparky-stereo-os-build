#!/bin/bash
# make-review-images.sh -- the main session's rerun images of lane 50f, from the base debian:testing image (7b0e755e) and
# the stage: sci50f-rig:1 (Debian's paraview and vtk9 on the published tree r1118a: the red rows), sci50f-rig:green-vtk
# (Debian's paraview on the edition's vtk9), sci50f-rig:green-pv2 (the edition's paraview +stereo3d2 and vtk9), sci50f-rig:green-i6b
# (jmol +stereo3d3 and python3-stereo-matplotlib 0.1.2). An image that exists is kept; remove it by name to remake it.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
have() { docker image inspect "$1" >/dev/null 2>&1; }
have sci50f-rig:1 || rig/make-rig.sh
V=stage/vtk9-9.6.2+ds-3+stereo3d1; P=stage/paraview-6.1.1+dfsg1-3+stereo3d2
have sci50f-rig:green-vtk || STAGE="$V" PKGS="libvtk9.6 libvtk9.6-qt" TAG=green-vtk rig/make-green.sh
have sci50f-rig:green-pv2 || RIG_CPUS=4 FROM=sci50f-rig:green-vtk STAGE="$V $P" PKGS="libvtk9.6 libvtk9.6-qt python3-vtk9 paraview python3-paraview" TAG=green-pv2 rig/make-green.sh
have sci50f-rig:green-i6b || STAGE="stage/jmol-16.3.55+dfsg-1+stereo3d3 stage/stereo-matplotlib-0.1.2" \
  PKGS="jmol libjmol-java python3-stereo-matplotlib" TAG=green-i6b rig/make-green.sh
docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}' | grep '^sci50f-'
