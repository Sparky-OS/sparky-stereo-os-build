#!/bin/bash
# Step 3's rows: the edition ParaView on the edition vtk9 (image $IMG, default sci50f-rig:green-pv), installed by apt.
# One fresh container and session per run. Any build container of the lane is paused meanwhile (four CPUs).
set -u
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=${IMG:-sci50f-rig:green-pv}; P=${P:-g3}
paused=
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- | head -1)
[ -n "$b" ] && docker pause "$b" >/dev/null && paused=$b
run() { rig/run-case.sh "$@" > /dev/null; }
EN=LANG=en_US.UTF-8; PT=LANG=pt_BR.UTF-8
OFF='{ "settings": { "GeneralSettings": { "AutoApply": 1 }, "RenderViewSettings": { "Enable3D": 0 } } }'
OLD='{ "settings": { "GeneralSettings": { "AutoApply": 1 } }, "views": { "RenderView": { "StereoRender": 1, "StereoType": 7 } } }'
# the default start: Enable 3D on, no option
for i in 1 2; do run pv-$P-default-wl-amd-$i $IMG pv-case.sh $EN; done
GPU=nvidia run pv-$P-default-wl-nv-1 $IMG pv-case.sh $EN
run pv-$P-default-x-amd-1 $IMG pv-case.sh QT_QPA_PLATFORM=xcb $EN
GPU=nvidia run pv-$P-default-x-nv-1 $IMG pv-case.sh QT_QPA_PLATFORM=xcb $EN
# --stereo --stereo-type="Crystal Eyes" as before
run pv-$P-ce-wl-amd-1 $IMG pv-case.sh "PV_STEREO=Crystal Eyes" $EN
# Enable 3D off
run pv-$P-off-wl-amd $IMG pv-case.sh "PV_SETTINGS=$OFF" $EN
run pv-$P-off-x-amd $IMG pv-case.sh "PV_SETTINGS=$OFF" QT_QPA_PLATFORM=xcb $EN
GPU=nvidia run pv-$P-off-wl-nv $IMG pv-case.sh "PV_SETTINGS=$OFF" $EN
GPU=nvidia run pv-$P-off-x-nv $IMG pv-case.sh "PV_SETTINGS=$OFF" QT_QPA_PLATFORM=xcb $EN
# the View menu, in English and in pt_BR (xcb, keys through xdotool)
run pv-$P-menu-x-amd-en $IMG pv-case.sh MENU=1 QT_QPA_PLATFORM=xcb $EN
run pv-$P-menu-x-amd-pt $IMG pv-case.sh MENU=1 QT_QPA_PLATFORM=xcb $PT
# the Settings dialog (Render View, searched for "stereo") and the main window with its Properties panel
run pv-$P-settings-en $IMG pv-settings-case.sh QT_QPA_PLATFORM=xcb $EN
run pv-$P-settings-pt $IMG pv-settings-case.sh SEARCH=3D QT_QPA_PLATFORM=xcb $PT   # ParaView searches the translated texts
# the six former output types on the command line, in English and pt_BR
run pv-$P-refuse-en $IMG pv-refuse-case.sh $EN
run pv-$P-refuse-pt $IMG pv-refuse-case.sh $PT
# an old saved setting naming Anaglyph, in English and pt_BR; an old state file (if made)
run pv-$P-oldsetting-wl-amd-en $IMG pv-case.sh "PV_SETTINGS=$OLD" $EN
run pv-$P-oldsetting-wl-amd-pt $IMG pv-case.sh "PV_SETTINGS=$OLD" $PT
if [ -f fixtures/anaglyph.pvsm ]; then
  run pv-$P-oldstate-wl-amd $IMG pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm $EN
  run pv-$P-oldstate-off-wl-amd $IMG pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm "PV_SETTINGS=$OFF" $EN
  run pv-$P-oldstate-wl-amd-pt $IMG pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm $PT
  run pv-red3-oldstate-wl-amd sci50f-rig:1 pv-case.sh PV_NODATA=1 PV_EXTRA=--state=/fixtures/anaglyph.pvsm $EN   # Debian's
fi
# a desktop that shows no 3D areas (a bare X server), in English and pt_BR
SESSION=pv-noareas-case.sh run pv-$P-noareas-en $IMG none $EN
SESSION=pv-noareas-case.sh run pv-$P-noareas-pt $IMG none $PT
[ -n "$paused" ] && docker unpause "$paused" >/dev/null
for d in runs/pv-$P-*/; do d=${d%/}
  [ -f $d/shot1.png ] || { echo "$(basename $d) (no capture)"; continue; }
  echo "$(basename $d) warnings=$(cat $d/drawbuffer-warnings.txt 2>/dev/null) set_content=$(grep -c set_content $d/wl.txt 2>/dev/null) windows=$(cut -d'|' -f2 $d/windows.txt | tr '\n' ';') $(python3 -I rig/pv_analyze.py $d | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print("stereo", d["stereo"], "measured", d.get("measured"), "pred", {k: d.get("prediction", {}).get(k) for k in ("near","far")}, "vert", d.get("disparity", {}).get("near_red", {}).get("y0"), d.get("disparity", {}).get("far_blue", {}).get("y0"), "diff_outside", d.get("differing_outside_view"))')"
done > runs/pv-$P-summary.txt
echo done
