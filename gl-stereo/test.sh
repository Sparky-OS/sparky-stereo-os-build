#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DOCKER_HOST=unix:///K3D/temp/partners/gl-stereo/docker.sock
workspace=$(cd .. && pwd)
repo=$PWD
protocols=/K3D/GitHub/sparky-stereo-os-build/plasma-wayland-protocols
container_name="gl-stereo-test-$(date +%s)-$$"
printf '%s\n' "$container_name" >> "$workspace/.artifacts"
container=$(docker run -d --name "$container_name" --user "$(id -u):$(id -g)" --cpus 4 \
    -e HOME="$repo/out/home" -e GL_STEREO_TEST_SCOPE="${GL_STEREO_TEST_SCOPE:-savers}" \
    -v "$workspace:$workspace" -v "$protocols:$protocols:ro" \
    -w "$repo" "${GL_STEREO_TEST_IMAGE:-gl-stereo-test:3}" ./test-in-container.sh)
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
docker logs "$container"
[ "$status" = 0 ]
