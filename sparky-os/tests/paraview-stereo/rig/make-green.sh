#!/bin/bash
# (copied from lane 50e and adapted: several stage folders, the base image FROM, dbgsym left out)
# usage: STAGE="DIR..." (or empty) PKGS="names" TAG=green-x make-green.sh  -- sci50f-rig:TAG = sci50f-rig:1 plus the staged packages installed
# by apt from a flat repository of the stage (Origin "Sparky Stereo OS", so the edition's pin applies as in a round), with
# apt's simulation of the install kept in $S/runs/apt-TAG.txt.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f; L=/K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f
export DOCKER_HOST=unix://$L/docker.sock
: "${STAGE?}" "${PKGS:?}" "${TAG:?}"   # STAGE may be empty: published and Debian packages only
F=$S/flat/$TAG; rm -rf "$F"; mkdir -p "$F"
for st in $STAGE; do cp "$st"/*.deb "$F/"; done; rm -f "$F"/*-dbgsym_*.deb
python3 -I $S/rig/flat-index.py "$F"
docker rm -f sci50f-mkgreen >/dev/null 2>&1 || true
docker run --name sci50f-mkgreen --pull=never --ulimit core=1 --cpus ${RIG_CPUS:-4} --platform linux/amd64 \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
  -v "$F":/flat:ro -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v $S/keys:/run/keys:ro -v $S/runs:/runs \
  -v /mnt/build/one-separation-outputs-750e/stage/stereo-declare:/sd:ro \
  ${FROM:-sci50f-rig:1} sh -c "set -e
  sh /run/https-only-apt.sh >/dev/null
  echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/stage.list
  apt-get update -qq 2>&1 | tail -3
  apt-get -s install -y $PKGS 2>&1 | grep -E '^(Inst|Remv|Conf)|upgraded|newly installed' > /runs/apt-$TAG.txt || true
  apt-get install -y -q $PKGS > /tmp/inst.log 2>&1 || { tail -20 /tmp/inst.log; exit 1; }
  dpkg-query -W $PKGS"
docker rmi sci50f-rig:$TAG >/dev/null 2>&1 || true
docker commit sci50f-mkgreen sci50f-rig:$TAG >/dev/null
grep -qx sci50f-rig:$TAG $L/.artifacts || echo sci50f-rig:$TAG >> $L/.artifacts
docker inspect -f '{{.Id}}' sci50f-mkgreen >> $L/.container-ids; docker rm sci50f-mkgreen >/dev/null
cat $S/runs/apt-$TAG.txt
