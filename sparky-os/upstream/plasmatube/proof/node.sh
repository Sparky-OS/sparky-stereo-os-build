#!/bin/bash
# usage: node.sh <bash command>: Node + pnpm + Debian testing's FFmpeg in a container, the PeerTube clone mounted at /pt, as my user
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/tmp/h -e CI=1 \
  -v /K3D/temp/partners/queue/plasmatube:/w -v /K3D/temp/partners/queue/plasmatube/peertube:/pt -w /pt pt-node:1 bash -c "mkdir -p /tmp/h && $1"
