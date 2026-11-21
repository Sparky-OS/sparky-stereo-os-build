#!/bin/bash
# Continuation 2 (row 50f): after c2-build.sh, the review images of the three successors and their rows.
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
until grep -q 'c2-build done' work/c2-build.log 2>/dev/null; do sleep 30; done
V=stage/vtk9-9.6.2+ds-3+stereo3d1; P=stage/paraview-6.1.1+dfsg1-3+stereo3d2
J=stage/jmol-16.3.55+dfsg-1+stereo3d3; M=stage/stereo-matplotlib-0.1.2
RIG_CPUS=4 FROM=sci50f-rig:green-vtk STAGE="$V $P" PKGS="libvtk9.6 libvtk9.6-qt python3-vtk9 paraview python3-paraview" \
  TAG=green-pv2 rig/make-green.sh > work/make-green-pv2.log 2>&1 || echo "green-pv2 failed"
RIG_CPUS=4 STAGE="$J $M" PKGS="jmol libjmol-java python3-stereo-matplotlib" TAG=green-i6b rig/make-green.sh \
  > work/make-green-i6b.log 2>&1 || echo "green-i6b failed"
run() { rig/run-case.sh "$@" > /dev/null; }
EN=LANG=en_US.UTF-8; PT=LANG=pt_BR.UTF-8; PV=sci50f-rig:green-pv2; I6=sci50f-rig:green-i6b
OFF='{ "settings": { "GeneralSettings": { "AutoApply": 1 }, "RenderViewSettings": { "Enable3D": 0 } } }'
OLD='{ "settings": { "GeneralSettings": { "AutoApply": 1 } }, "views": { "RenderView": { "StereoRender": 1, "StereoType": 7 } } }'
DOWN10="Down Down Down Down Down Down Down Down Down Down Return"
# 1. "3D display settings..." opens KScreen's page, from each program, in English and pt_BR
run c2-display-pv-en $PV pv-case.sh MENU=1 "MENU_KEYS=Up Return" QT_QPA_PLATFORM=xcb $EN
run c2-display-pv-pt $PV pv-case.sh MENU=1 "MENU_KEYS=Up Return" QT_QPA_PLATFORM=xcb $PT
run c2-display-jmol-en $I6 jmol-menu-case.sh MENU_X=150 MENU_Y=11 MENU_KEY=alt+d MENU_WAIT=4 "ACT_KEYS=$DOWN10" $EN
run c2-display-jmol-pt $I6 jmol-menu-case.sh MENU_X=150 MENU_Y=11 MENU_KEY=alt+m MENU_WAIT=4 "ACT_KEYS=$DOWN10" $PT LC_ALL=pt_BR.UTF-8
run c2-display-mpl-en $I6 mpl-case.sh MPLBACKEND=TkAgg ACT=display $EN
run c2-display-mpl-pt $I6 mpl-case.sh MPLBACKEND=TkAgg ACT=display $PT LC_ALL=pt_BR.UTF-8
# 2. Enable 3D switched off in the View menu, ParaView quit, started again
run c2-restart-x-amd $PV pv-restart-case.sh QT_QPA_PLATFORM=xcb $EN
# 3. an old screenshot stereo mode (pvpython)
run c2-shot-wl-amd $PV pv-shot-case.sh $EN
# 4. the old-setting and old-state notices on xcb and on the RTX 3060
run c2-oldsetting-x-amd $PV pv-case.sh "PV_SETTINGS=$OLD" QT_QPA_PLATFORM=xcb $EN
GPU=nvidia run c2-oldsetting-wl-nv $PV pv-case.sh "PV_SETTINGS=$OLD" $EN
GPU=nvidia run c2-oldsetting-x-nv $PV pv-case.sh "PV_SETTINGS=$OLD" QT_QPA_PLATFORM=xcb $EN
run c2-oldstate-x-amd $PV pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm QT_QPA_PLATFORM=xcb $EN
GPU=nvidia run c2-oldstate-wl-nv $PV pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm $EN
GPU=nvidia run c2-oldstate-x-nv $PV pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm QT_QPA_PLATFORM=xcb $EN
# 4b. two of the translations lane's sentences on screen: the old-setting notice in German, the no-3D-areas notice in
# Japanese
run c2-oldsetting-wl-amd-de $PV pv-case.sh "PV_SETTINGS=$OLD" LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8
SESSION=pv-noareas-case.sh run c2-noareas-ja $PV none LANG=ja_JP.UTF-8 LC_ALL=ja_JP.UTF-8
# 5. a flat view on Wayland, without and with the colour-size rule (the shim over the edition's vtk9)
run c2-off-wl-amd $PV pv-case.sh "PV_SETTINGS=$OFF" $EN
run c2-off-wl-amd-shimfix $PV pv-case.sh "PV_SETTINGS=$OFF" LD_PRELOAD=/rig/libcolour-size-shim.so COLOUR_SIZE_SHIM=fix $EN
# 6. the edition rows again on the successor, Jmol's and the module's pair, apt's upgrade plan
IMG=$PV P=c2g rig/g3-batch.sh > work/g3-c2.log 2>&1
run c2-jm-pair $I6 jmol-case.sh $EN
run c2-mpl-tk-pair $I6 mpl-case.sh MPLBACKEND=TkAgg $EN
STAGE="$S/$V $S/$P" rig/apt-upgrade-sim.sh > work/apt-upgrade-sim-c2.log 2>&1
for pair in "pv-c2g-off-wl-amd pv-red2-mono-wl-amd" "pv-c2g-off-x-amd pv-red2-mono-x-amd"; do
  set -- $pair; python3 -I rig/view_equal.py runs/$1 runs/$2
done > runs/view-equal-c2.txt
echo "c2-rows done"
