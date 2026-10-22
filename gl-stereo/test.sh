#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
export DOCKER_HOST=unix://${SPARKY_SCRATCH:?}/partners/gl-stereo/docker.sock
workspace=$(cd .. && pwd)
repo=$PWD
protocols=${SPARKY_TREE:?}/plasma-wayland-protocols
container_name="gl-stereo-test-$(date +%s)-$$"
printf '%s\n' "$container_name" >> "$workspace/.artifacts"
container=$(docker run -d --name "$container_name" --user "$(id -u):$(id -g)" --cpus 4 \
    -e HOME="$repo/out/home" -e STEREO_DECLARE_SOURCE="$protocols/stereo-declare" -e GL_STEREO_TEST_SCOPE="${GL_STEREO_TEST_SCOPE:-savers}" \
    -v "$workspace:$workspace" -v "$protocols:$protocols:ro" \
    -w "$repo" "${GL_STEREO_TEST_IMAGE:-gl-stereo-test:3}" ./test-in-container.sh)
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
docker logs "$container"
[ "$status" = 0 ]
