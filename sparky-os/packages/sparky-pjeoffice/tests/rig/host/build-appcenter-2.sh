#!/bin/bash
# second pass of the app center build: from the first pass's own .dsc, so the build record gets its buildinfo (skill edition-packaging, app-center-entry-tools)
set -euo pipefail
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
BT=/K3D/partners/queue/pje-office-2/src/build
OUT=/var/tmp/pje-office-18/out/appcenter
OUT2=/var/tmp/pje-office-18/out/appcenter2
SCRATCH=/var/tmp/pje-office-18/linkscratch
IMAGE=pj18-build:2
rm -rf "$OUT2"; mkdir -p "$OUT2"
. "$BT/sparky-os/repo/build-provenance.sh"
cd "$BT/sparky-os/packages/sparky-aptus-stereo-appcenter"
SPARKY_PROVENANCE_REQUIRED=1 sparky_provenance_init "$IMAGE" "$PWD"
docker run --rm --name pj18-build-ac2 --pull=never --ulimit core=0 --cpus 4 --user "$(id -u):$(id -g)" -e HOME="$SCRATCH/home" \
  -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH="$SCRATCH/link" "${SPARKY_PROV_ARGS[@]}" \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
  -v /var/tmp/pje-office-18/archive:/archive:ro -v /K3D/sparky-repo-r1117a:/repo:ro -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro \
  -v "$OUT":/first:ro -v "$OUT2":/work -v "$SCRATCH":"$SCRATCH" -v "$BT":"$BT":ro -v /etc/passwd:/etc/passwd:ro "$IMAGE" sh -c "
set -e; cd /work; dpkg-source -x /first/sparky-aptus-stereo-appcenter_0.1.13+lc1.dsc src >/dev/null
cd src && PYTHONPATH='$BT/sparky-os' dpkg-buildpackage -us -uc -b > /work/build.log 2>&1 || { tail -30 /work/build.log; exit 1; }
cd /work && ls; PYTHONPATH='$BT/sparky-os' python3 -m lean.release check-debs ./*.deb"
