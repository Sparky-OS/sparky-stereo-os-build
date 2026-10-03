#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DOCKER_HOST=unix:///K3D/temp/partners/gl-stereo/docker.sock
workspace=$(cd .. && pwd)
repo=$PWD
protocols=/K3D/GitHub/sparky-stereo-os-build/plasma-wayland-protocols
container=$(docker run -d --cpus 4 -v "$workspace:$workspace" -v "$protocols:$protocols:ro" \
    -w "$repo" debian:testing ./test-in-container.sh)
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
docker logs "$container"
[ "$status" = 0 ]
