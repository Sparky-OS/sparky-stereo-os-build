#!/bin/bash
# run-test.sh IMAGE NAME SCRIPT...  : a disposable container with the package folder at /pkg (ro) and /fx (rw scratch)
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
PKG=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
FX=/var/tmp/pje-office-18/fx-$2-$(date +%s); mkdir -p "$FX"
docker rm -f "$2" >/dev/null 2>&1
docker run --rm --name "$2" --pull=never --ulimit core=1 --network none --platform linux/amd64 --mount type=bind,src=$PKG,dst=/pkg,readonly \
  --mount type=bind,src=$FX,dst=/fx --mount type=bind,src=/var/tmp/pje-office-18/bin,dst=/tb,readonly --mount type=bind,src=/var/tmp/pje-office-18/x,dst=/real,readonly --tmpfs /run:exec -e HOME=/root "$1" bash -c "${@:3}; rc=\$?; chown -R $(id -u):$(id -g) /fx; exit \$rc"
