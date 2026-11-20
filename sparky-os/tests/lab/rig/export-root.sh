#!/bin/bash
# export-root.sh IMAGE DIR: unpacks an image's file system into DIR (the guest shares it read only over 9p).
# Needs DOCKER_HOST (the lane socket). The temporary container is lab22-export-root, removed after.
set -euo pipefail
IMG=$1 DIR=$2
: "${DOCKER_HOST:?set DOCKER_HOST}"
rm -rf "$DIR"; mkdir -p "$DIR"
docker rm -f lab22-export-root >/dev/null 2>&1 || true
docker create --name lab22-export-root --pull=never --ulimit core=1 "$IMG" /bin/true >/dev/null
docker export lab22-export-root | tar -C "$DIR" --exclude='./dev/*' --exclude='./proc/*' --exclude='./sys/*' -xf - 2>/dev/null || true
docker rm lab22-export-root >/dev/null
chmod -R u+rwX "$DIR" 2>/dev/null || true
du -sx --block-size=1M "$DIR"
