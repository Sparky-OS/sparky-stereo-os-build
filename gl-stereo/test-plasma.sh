#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
export DOCKER_HOST=unix://${SPARKY_SCRATCH:?}/partners/gl-stereo/docker.sock
workspace=$(cd .. && pwd)
repo=$PWD
protocols=${SPARKY_TREE:?}/plasma-wayland-protocols
power=${SPARKY_TREE:?}/sparky-os/packages/sparky-stereo-power-profiles/share
mkdir -p out/plasma/power-defaults
cp "$power/powerdevilrc" "$power/kscreenlockerrc" out/plasma/power-defaults/
container_name="gl-stereo-plasma-proof-$(date +%s)-$$"
printf '%s\n' "$container_name" >> "$workspace/.artifacts"
container=$(docker run -d --init --name "$container_name" --user "$(id -u):$(id -g)" --group-add "${GL_STEREO_RENDER_GID:-125}" --cpus 4 \
    --device /dev/dri/renderD128 -e STEREO_DECLARE_SOURCE="$protocols/stereo-declare" -v "$workspace:$workspace" -v "$protocols:$protocols:ro" \
    -w "$repo" gl-stereo-plasma:4 bash -c 'bash plasma/verify.sh >out/plasma/verify.log 2>&1; rc=$?; python3 plasma/cleanup-cache.py; echo "$rc" >out/plasma/verify.status; exit "$rc"')
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
docker logs "$container"
[ "$status" = 0 ]
