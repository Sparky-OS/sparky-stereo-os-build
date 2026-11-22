#!/bin/bash
# (copied from lane 50e and adapted: several stage folders, the base image FROM, dbgsym left out, the frozen sources)
# usage: STAGE="DIR..." (or empty) PKGS="names" TAG=green-x [FROM=image] make-green.sh  -- sci50f-rig:TAG = FROM (default
# sci50f-rig:1) plus the staged packages installed by apt from a flat repository of the stage (Origin "Sparky Stereo OS", so
# the edition's pin applies as in a round), with the snapshot's Debian (the image's own sources: rig/prelude.sh) and the
# frozen deb-multimedia. apt's simulation of the install goes to runs/apt-TAG.txt, the dist-upgrade simulation of the result
# to runs/apt-distupgrade-TAG.txt (0 upgraded and 0 not upgraded expected).
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
: "${STAGE?}" "${PKGS:?}" "${TAG:?}"   # STAGE may be empty: published and Debian packages only
F=$S/flat/$TAG; rm -rf "$F"; mkdir -p "$F"
for st in $STAGE; do cp "$st"/*.deb "$F/"; done; rm -f "$F"/*-dbgsym_*.deb
python3 -I $S/rig/flat-index.py "$F"
C=sci50f-mkgreen-$$
gone() { docker inspect -f '{{.Id}}' $C >> $L/.container-ids 2>/dev/null && docker rm -f $C >/dev/null 2>&1 || true; }
trap gone EXIT
docker run --name $C --pull=never --ulimit core=1 --cpus ${RIG_CPUS:-4} --platform linux/amd64 \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
  -v "$F":/flat:ro -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v $S/frozen/dmo:/dmo:ro -v $S/keys:/run/keys:ro -v $S/runs:/runs \
  ${FROM:-sci50f-rig:1} sh -c "set -e
  sh /run/https-only-apt.sh >/dev/null
  echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/stage.list
  apt-get update -qq 2>&1 | tail -3
  apt-get -s install -y $PKGS 2>&1 | grep -E '^(Inst|Remv|Conf)|upgraded|newly installed' > /runs/apt-$TAG.txt || true
  apt-get install -y -q $PKGS > /tmp/inst.log 2>&1 || { tail -20 /tmp/inst.log; exit 1; }
  { echo \"snapshot \$(cat /etc/apt/sci50f-snapshot)\"; apt-get -s dist-upgrade | grep -E '^(Inst|Remv)|upgraded'; } > /runs/apt-distupgrade-$TAG.txt
  chown 1000:1000 /runs/apt-$TAG.txt /runs/apt-distupgrade-$TAG.txt; tail -1 /runs/apt-distupgrade-$TAG.txt
  dpkg-query -W $PKGS; apt-get clean"
docker commit $C sci50f-rig:$TAG >/dev/null
grep -qx sci50f-rig:$TAG $L/.artifacts || echo sci50f-rig:$TAG >> $L/.artifacts
cat $S/runs/apt-$TAG.txt | tail -3
