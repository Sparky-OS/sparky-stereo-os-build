#!/bin/bash
# Item 6 on the final packages (jmol +stereo3d2 with patch 0003, python3-stereo-matplotlib 0.1.1, both from commit
# 8efe1bbd62): i6-batch.sh's rows (the pair, the told-once sentences in de and ja, the loaders of all eight languages),
# then Jmol's Display menu opened over the 3D area in de, ja and en with Enable 3D on, and in de and ja with it off.
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=sci50f-rig:green-i6
rig/i6-batch.sh
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- --filter status=running | head -1); [ -n "$b" ] && docker pause "$b" >/dev/null
run() { rig/run-case.sh "$@" > /dev/null; }
run jm-i6-menu-de_DE $IMG jmol-menu-case.sh MENU_X=178 MENU_Y=11 MENU_KEY=alt+a MENU_KEY2=Left MENU_WAIT=8 LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8
run jm-i6-menu-ja_JP $IMG jmol-menu-case.sh MENU_X=158 MENU_Y=13 MENU_KEY=alt+d MENU_WAIT=8 LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8
run jm-i6-menu-en $IMG jmol-menu-case.sh MENU_X=150 MENU_Y=11 MENU_KEY=alt+d MENU_WAIT=8 LANG=en_US.UTF-8
run jm-i6-menu-de_DE-off $IMG jmol-menu-case.sh MENU_X=178 MENU_Y=11 MENU_KEY=alt+a MENU_KEY2=Left MENU_WAIT=8 ENABLE3D=0 LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8
run jm-i6-menu-ja_JP-off $IMG jmol-menu-case.sh MENU_X=158 MENU_Y=13 MENU_KEY=alt+d MENU_WAIT=8 ENABLE3D=0 LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8
for l in de_DE ja_JP; do run mpl-i6-qtwl-wide-$l $IMG mpl-case.sh MPLBACKEND=QtAgg FIGW=16 LANG=$l.UTF-8 LC_ALL=$l.UTF-8; done
[ -n "$b" ] && docker unpause "$b" >/dev/null
for d in runs/jm-i6-menu-*; do echo "$(basename $d) $(python3 -I rig/jmol_analyze.py $d 2>&1 | head -c 300)"; done >> runs/i6-summary.txt
echo done
