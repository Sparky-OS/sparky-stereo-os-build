#!/bin/bash
# vtk9-s2-after.sh -- after the vtk9 +stereo3d2 build (continuation 3): the build's exit and record checked; its source closure
# staged at stage/vtk9-9.6.2+ds-3+stereo3d2 and +stereo3d1 moved to ref/ with its sums; both compared file by file
# (+stereo3d2 against +stereo3d1 and against Debian's 9.6.2+ds-3: paths, owners and modes, bytes, ELF NEEDED, SONAME and
# defined dynamic symbols, control fields); the build tree measured and removed by its path; then the review images that
# carry vtk9 remade (green-vtk, green-pv2) and pv2-ref made (paraview +stereo3d2 on +stereo3d1, for the red rows).
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
W=/mnt/games/k3d-temp/build/science-paraview-50f/vtk9/pkg; V=9.6.2+ds-3+stereo3d2
grep -q 'container exit 0' build/out-vtk9/exit.txt
python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['recipeDirty'] is False, d['recipeDirty']; print('record', d.get('recipeCommit') or d.get('commit'))" $W/vtk9_${V}+lc1_amd64.sparky-build.json
python3 -I rig/stage.py $W stage/vtk9-$V $W/vtk9_${V}+lc1_amd64.changes build/out-vtk9/recipe.log
(cd stage/vtk9-$V && sha256sum -c --quiet SHA256SUMS)
mkdir -p ref; [ -d stage/vtk9-9.6.2+ds-3+stereo3d1 ] && mv stage/vtk9-9.6.2+ds-3+stereo3d1 ref/
(cd ref/vtk9-9.6.2+ds-3+stereo3d1 && sha256sum -c --quiet SHA256SUMS)
mkdir -p work/cmp3
PREV_LABEL=+stereo3d1 python3 -I rig/compare-debs.py ref/vtk9-9.6.2+ds-3+stereo3d1 stage/vtk9-$V work/cmp3 work/cmp3/vtk9-s2-vs-s1.txt
python3 -I rig/compare-debs.py debian-debs stage/vtk9-$V work/cmp3 work/cmp3/vtk9-s2-vs-debian.txt
cat work/vtk9-space.log > work/vtk9-s2-space.txt 2>/dev/null || true
timeout 300 du -sm /mnt/games/k3d-temp/build/science-paraview-50f/vtk9 > work/vtk9-s2-tree-size.txt || true
rm -rf /mnt/games/k3d-temp/build/science-paraview-50f/vtk9
du -sm stage/vtk9-$V >> work/vtk9-s2-tree-size.txt
RIG_CPUS=4 rig/make-review-images.sh green-vtk green-pv2 pv2-ref
echo "vtk9-s2-after done"
