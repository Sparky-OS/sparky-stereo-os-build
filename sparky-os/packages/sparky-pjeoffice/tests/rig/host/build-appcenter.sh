#!/bin/bash
# build the app center package 0.1.13 from the fork's branch, with the recipe's own build.sh, in a pj18-build container
set -euo pipefail
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
BT=/K3D/partners/queue/pje-office-2/src/build
AC=/K3D/partners/queue/pje-office-2/src/appcenter
OUT=/var/tmp/pje-office-18/out/appcenter
SCRATCH=/var/tmp/pje-office-18/linkscratch
IMAGE=pj18-build:2
rm -rf "$OUT"; mkdir -p "$OUT" "$SCRATCH"
. "$BT/sparky-os/repo/build-provenance.sh"
cd "$BT/sparky-os/packages/sparky-aptus-stereo-appcenter"
SPARKY_PROVENANCE_REQUIRED=1 sparky_provenance_init "$IMAGE" "$PWD"
docker run --rm --name pj18-build-ac --pull=never --ulimit core=1 --cpus 4 --user "$(id -u):$(id -g)" -e HOME="$SCRATCH/home" -e OUT="$OUT" \
  -e APTUS_SOURCE="$AC" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH="$SCRATCH/link" \
  "${SPARKY_PROV_ARGS[@]}" --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
  -v /var/tmp/pje-office-18/archive:/archive:ro -v /K3D/sparky-repo-r1117a:/repo:ro -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro \
  -v "$BT":"$BT":ro -v "$AC":"$AC":ro -v "$OUT":"$OUT" -v "$SCRATCH":"$SCRATCH" -v /etc/passwd:/etc/passwd:ro \
  "$IMAGE" sh -c "mkdir -p $SCRATCH/home $SCRATCH/link; git config --global --add safe.directory '*'; cd '$PWD' && bash ./build.sh && cd '$OUT' && PYTHONPATH='$BT/sparky-os' python3 -m lean.release check-debs ./*.deb"
