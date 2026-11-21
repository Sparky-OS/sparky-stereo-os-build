#!/bin/bash
# After a jmol build: its closure staged (the old stage folder removed by its path), compared file by file with step 4's
# +stereo3d1, its build tree removed, sci50f-rig:green-i6 made again from the stage, item 6's rows run (i6-batch2.sh).
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
W=/mnt/games/k3d-temp/build/science-paraview-50f/jmol/pkg
grep -q '"recipeDirty": false' $W/jmol_16.3.55+dfsg-1+stereo3d2+lc1_amd64.sparky-build.json
rm -rf /var/lib/sparky-lanes/science-paraview-50f/stage/jmol-16.3.55+dfsg-1+stereo3d2
python3 -I rig/stage.py $W stage/jmol-16.3.55+dfsg-1+stereo3d2 $W/jmol_16.3.55+dfsg-1+stereo3d2+lc1_all.changes build/out-jmol/recipe.log
PREV_LABEL="step 4's +stereo3d1" python3 -I rig/compare-debs.py /var/lib/sparky-lanes/science-jmol-matplotlib-paraview-50e/stage/jmol-16.3.55+dfsg-1+stereo3d1 \
  stage/jmol-16.3.55+dfsg-1+stereo3d2 work/cmp work/cmp/jmol-stereo3d2-vs-stereo3d1.txt
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/jmol
RIG_CPUS=1 STAGE="stage/jmol-16.3.55+dfsg-1+stereo3d2 stage/stereo-matplotlib-0.1.1" PKGS="jmol libjmol-java python3-stereo-matplotlib" \
  TAG=green-i6 rig/make-green.sh > work/make-green-i6.log 2>&1
rig/i6-batch2.sh
