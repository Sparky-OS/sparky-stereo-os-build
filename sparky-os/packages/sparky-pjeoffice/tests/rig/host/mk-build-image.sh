#!/bin/bash
set -euo pipefail
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
BASE=gr108-base:testing-20261027
docker image inspect "$BASE" >/dev/null
docker rm -f pj18-mkbuild >/dev/null 2>&1 || true
docker run --name pj18-mkbuild --pull=never --ulimit core=0 --platform linux/amd64 \
  -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
  --mount type=bind,src=/K3D/sparky-repo-r1117a,dst=/repo,readonly \
  -v /K3D/GitHub/sparky-stereo-os-build/sparky-os/apt/sparky-stereo:/run/pin:ro \
  "$BASE" sh -ec '
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
apt-get update -q && apt-get -y -q install --no-install-recommends ca-certificates gnupg
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/sparky-stereo-repo.asc
cat > /etc/apt/sources.list.d/sparky-stereo.sources <<S
Types: deb
URIs: file:///repo
Suites: mashtabba
Components: main
Signed-By: /usr/share/keyrings/sparky-stereo-repo.asc
S
cp /run/pin /etc/apt/preferences.d/sparky-stereo
sh /run/https-only-apt.sh
apt-get update -q
apt-cache policy sparky-stereo-problems qt6-base-dev | head -12
'
