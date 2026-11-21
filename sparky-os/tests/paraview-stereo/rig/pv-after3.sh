#!/bin/bash
# After the paraview rebuild with the revised patch 0003: the closure staged again (the earlier stage folder removed by its path),
# compared with Debian's, the tree removed; then: sci50f-rig:green-pv made again, the
# edition ParaView's rows (g3-batch.sh), apt's simulated upgrade and the render-view comparisons.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
until grep -q 'paraview runner exit' work/run-paraview3.log 2>/dev/null; do sleep 30; done
grep -q 'container exit 0' build/out-paraview/exit.txt
W=/mnt/games/k3d-temp/build/science-paraview-50f/paraview/pkg
grep -q '"recipeDirty": false' $W/paraview_6.1.1+dfsg1-3+stereo3d1+lc1_amd64.sparky-build.json
rm -rf /var/lib/sparky-lanes/science-paraview-50f/stage/paraview-6.1.1+dfsg1-3+stereo3d1
python3 -I rig/stage.py $W stage/paraview-6.1.1+dfsg1-3+stereo3d1 $W/paraview_6.1.1+dfsg1-3+stereo3d1+lc1_amd64.changes build/out-paraview/recipe.log
python3 -I rig/compare-debs.py debian-debs stage/paraview-6.1.1+dfsg1-3+stereo3d1 work/cmp work/cmp/paraview-vs-debian.txt
timeout 300 du -sm /mnt/games/k3d-temp/build/science-paraview-50f/paraview > work/paraview-tree-size.txt || true
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/paraview

RIG_CPUS=4 FROM=sci50f-rig:green-vtk STAGE="stage/vtk9-9.6.2+ds-3+stereo3d1 stage/paraview-6.1.1+dfsg1-3+stereo3d1" \
  PKGS="libvtk9.6 libvtk9.6-qt paraview" TAG=green-pv rig/make-green.sh > work/make-green-pv.log 2>&1
rig/g3-batch.sh > work/g3.log 2>&1
rig/apt-upgrade-sim.sh > work/apt-upgrade-sim.log 2>&1
for pair in "pv-green-mono-wl-amd pv-red2-mono-wl-amd" "pv-green-mono-x-amd pv-red2-mono-x-amd" \
            "pv-g3-off-wl-amd pv-red2-mono-wl-amd" "pv-g3-off-x-amd pv-red2-mono-x-amd"; do
  set -- $pair; python3 -I rig/view_equal.py runs/$1 runs/$2
done > runs/view-equal.txt
echo "pv-after3 done"
