#!/bin/bash
# The View menu's two edition actions on the installed edition ParaView (xcb, keys through xdotool), English and pt_BR:
# "Enable 3D" (its restart notice) and "3D display settings..." (KScreen, or the sentence when it cannot start).
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=${IMG:-sci50f-rig:green-pv}
run() { rig/run-case.sh "$@" > /dev/null; }
for l in en:en_US.UTF-8 pt:pt_BR.UTF-8; do
  run pv-act-enable3d-x-amd-${l%%:*} $IMG pv-case.sh MENU=1 "MENU_KEYS=Up Up Return" QT_QPA_PLATFORM=xcb LANG=${l#*:}
  run pv-act-display-x-amd-${l%%:*} $IMG pv-case.sh MENU=1 "MENU_KEYS=Up Return" QT_QPA_PLATFORM=xcb LANG=${l#*:}
done
echo "menu-act done"
