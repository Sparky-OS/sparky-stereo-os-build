#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DOCKER_HOST=unix:///K3D/temp/partners/gl-stereo/docker.sock
workspace=$(cd .. && pwd)
repo=$PWD
protocols=/K3D/GitHub/sparky-stereo-os-build/plasma-wayland-protocols
power=/K3D/GitHub/sparky-stereo-os-build/sparky-os/packages/sparky-stereo-power-profiles/share
mkdir -p out/plasma/power-defaults
cp "$power/powerdevilrc" "$power/kscreenlockerrc" out/plasma/power-defaults/
container_name="gl-stereo-plasma-proof-$(date +%s)-$$"
printf '%s\n' "$container_name" >> "$workspace/.artifacts"
container=$(docker run -d --init --name "$container_name" --user "$(id -u):$(id -g)" --group-add "${GL_STEREO_RENDER_GID:-125}" --cpus 4 \
    --device /dev/dri/renderD128 -v "$workspace:$workspace" -v "$protocols:$protocols:ro" \
    -w "$repo" gl-stereo-plasma:4 bash -c 'bash plasma/verify.sh >out/plasma/verify.log 2>&1; rc=$?; python3 plasma/cleanup-cache.py; echo "$rc" >out/plasma/verify.status; exit "$rc"')
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
docker logs "$container"
[ "$status" = 0 ]
