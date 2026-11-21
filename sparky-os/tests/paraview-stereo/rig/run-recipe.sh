#!/bin/bash
# usage: run-recipe.sh vtk9|paraview|jmol|stereo-matplotlib   -- host side: provenance (build-provenance.sh), then the
# recipe's build.sh in a builder container, then the Lean Code release gate (check-debs) on the packages. The build tree
# goes to $WORKROOT/NAME (default /mnt/games/k3d-temp/build/science-paraview-50f), with the temporary folder and the link
# gate's scratch inside it (TMPDIR, SPARKY_LC_SCRATCH), so nothing large lands on the root disk; the logs go to this
# lane's scratch.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
BT=$L/src/sparky-stereo-os-build
NAME=${1:?vtk9, paraview, jmol or stereo-matplotlib}
IMAGE=${IMAGE:-sci50f-builder:1}
WORKROOT=${WORKROOT:-/mnt/games/k3d-temp/build/science-paraview-50f}
. $BT/sparky-os/repo/build-provenance.sh
SPARKY_PROVENANCE_REQUIRED=1 sparky_provenance_init "$IMAGE" $BT/sparky-os/packages/$NAME
W=$WORKROOT/$NAME; O=$S/build/out-$NAME; G=$S/build/gate-$NAME
[ ! -e "$W" ] || { echo "$W exists: remove it first (by its literal path)" >&2; exit 1; }
mkdir -p "$W" "$O" "$G"; printf '%s\n' ${SIBLINGS:-} > "$O/siblings.txt"; sed -i '/^$/d' "$O/siblings.txt"
grep -qx "$WORKROOT" $L/.artifacts || echo "$WORKROOT" >> $L/.artifacts
case $NAME in
  vtk9) cmd="bash /tree/sparky-os/packages/vtk9/build.sh /dsc/vtk9_9.6.2+ds-3.dsc /work/pkg" ;;
  paraview) cmd="bash /tree/sparky-os/packages/paraview/build.sh /dsc/paraview_6.1.1+dfsg1-3.dsc /work/pkg" ;;
  jmol) cmd="bash /tree/sparky-os/packages/jmol/build.sh /jmolsrc/jmol_16.3.55+dfsg-1.dsc /work/pkg" ;;
  stereo-matplotlib) cmd="OUT=/work/pkg bash /tree/sparky-os/packages/stereo-matplotlib/build.sh" ;;
  *) cmd="bash /tree/sparky-os/packages/$NAME/build.sh ${RECIPE_ARGS:-} /work/pkg" ;;
esac
pre=${PRE:-true}
started=$(date --iso-8601=seconds)
docker run --name sci50f-build-$NAME --pull=never --ulimit core=1 --cpus ${CPUS:-4} --platform linux/amd64 \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
  "${SPARKY_PROV_ARGS[@]}" \
  -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro -v $S/keys:/run/keys:ro \
  -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v $BT:/tree:ro -v $S/src/debian:/dsc:ro -v $S/rig:/rig:ro -v $S/src/jmol:/jmolsrc:ro -v /mnt/build/one-separation-outputs-750e/stage/stereo-declare:/sd:ro \
  -v /var/lib/sparky-lanes/sparky-repo-r1118a/pool/main/s:/pool-s:ro \
  ${EXTRA_MOUNTS:-} -v "$W":/work -v "$O":/out -v "$G":/gate \
  -e HOME=/work/home -e TMPDIR=/work/tmp -e TREE=/tree/sparky-os -e SPARKY_LC_ARCHIVE_CONFIG=/rig/archive.json -e SPARKY_LC_SCRATCH=/work/gate \
  -e SPARKY_LC_SIBLINGS_FILE=/out/siblings.txt -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/out/siblings.txt \
  -e "DEB_BUILD_OPTIONS=${BUILD_OPTS:-parallel=4 nocheck}" \
  "$IMAGE" bash -c "trap 'chown -R 1000:1000 /work /out /gate 2>/dev/null' EXIT; set -o pipefail; mkdir -p /work/home /work/pkg /work/tmp /work/gate && git config --global --add safe.directory '*' && $pre && \
    $cmd > /out/recipe.log 2>&1; rc=\$?; echo recipe rc=\$rc >> /out/recipe.log; [ \$rc = 0 ] || exit \$rc; \
    cd /work/pkg && PYTHONPATH=/tree/sparky-os python3 -m lean.release check-debs /work/pkg/*+lc1_*.deb > /out/check-debs.log 2>&1; \
    rc=\$?; echo check-debs rc=\$rc >> /out/check-debs.log; exit \$rc" || true
docker inspect -f '{{.Id}}' sci50f-build-$NAME >> $L/.container-ids
echo "container exit $(docker inspect -f '{{.State.ExitCode}}' sci50f-build-$NAME), started $started, ended $(date --iso-8601=seconds)" | tee "$O/exit.txt"
docker rm sci50f-build-$NAME >/dev/null
coredumpctl list -q --since "$started" 2>/dev/null | tee "$O/coredumps.txt" || true
tail -3 "$O/recipe.log"; tail -3 "$O/check-debs.log" 2>/dev/null || true
