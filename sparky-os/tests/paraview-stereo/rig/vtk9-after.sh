#!/bin/bash
# After the vtk9 build: its closure staged and compared file by file with Debian's packages, its build tree removed, the
# paraview build started (three CPUs), sci50f-rig:green-vtk made (one CPU) and the green rows of step 2 run on it (the
# reproducer, Debian's paraview on the edition's vtk9, the mono starts), then the rows of the programs that load vtk9.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
W=/mnt/games/k3d-temp/build/science-paraview-50f/vtk9/pkg
grep -q 'container exit 0' build/out-vtk9/exit.txt
grep -q '"recipeDirty": false' $W/vtk9_9.6.2+ds-3+stereo3d1+lc1_amd64.sparky-build.json
python3 -I rig/stage.py $W stage/vtk9-9.6.2+ds-3+stereo3d1 $W/vtk9_9.6.2+ds-3+stereo3d1+lc1_amd64.changes build/out-vtk9/recipe.log
python3 -I rig/compare-debs.py debian-debs stage/vtk9-9.6.2+ds-3+stereo3d1 work/cmp work/cmp/vtk9-vs-debian.txt
timeout 300 du -sm /mnt/games/k3d-temp/build/science-paraview-50f/vtk9 > work/vtk9-tree-size.txt || true
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/vtk9
( CPUS=3 EXTRA_MOUNTS="-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro" \
  PRE="apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get build-dep -y -q paraview=6.1.1+dfsg1-3 > /out/pre.log 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends gettext >> /out/pre.log 2>&1" \
  rig/run-recipe.sh paraview > work/run-paraview.log 2>&1; echo "paraview runner exit $?" >> work/run-paraview.log ) &
RIG_CPUS=1 STAGE="stage/vtk9-9.6.2+ds-3+stereo3d1" PKGS="libvtk9.6 libvtk9.6-qt" TAG=green-vtk rig/make-green.sh > work/make-green-vtk.log 2>&1
IMG=sci50f-rig:green-vtk P=green rig/qb-batch.sh > work/qb-green.log 2>&1
IMG=sci50f-rig:green-vtk P=green rig/red-batch.sh > work/pv-green.log 2>&1
free=$(df -B1M --output=avail / | tail -1 | tr -d ' ')
if [ "$free" -ge 8192 ]; then rig/vtk-progs-batch.sh > work/vtk-progs.log 2>&1 || true
else echo "programs rows not started: / has $free MB free, under 8 GB for their four images" | tee work/vtk-progs.log; fi
echo "vtk9-after done"
