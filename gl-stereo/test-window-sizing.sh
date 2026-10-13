#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
export DOCKER_HOST=unix:///K3D/temp/partners/gl-stereo/docker.sock
workspace=$(cd .. && pwd)
repo=$PWD
rig=/K3D/temp/partners/queue/kwin-package-17/m2/rig
./test.sh >out/window-sizing-savers.log 2>&1
name="gl-stereo-sizing-$(date +%s)-$$"
printf '%s\n' "$name" >> "$workspace/.artifacts"
container=$(docker run -d --init --name "$name" --user "$(id -u):$(id -g)" --group-add 125 --cpus 4 \
    --device /dev/dri/renderD128 -v "$workspace:$workspace" -v "$rig:/rig:ro" \
    -v "$rig/passwd:/etc/passwd:ro" -v "$rig/group:/etc/group:ro" \
    -w "$repo" gl-stereo-sizing:1 bash -c '
        ulimit -c 0
        gcc -O2 -Wall -Wextra tests/window-sizing.c -o out/window-sizing/client -lGL -lX11 -ldl &&
        for name in before after quad future gears; do
            python3 tests/run-window-rig.py "$name" >"out/window-sizing/$name.log" 2>&1 || exit
        done &&
        python3 tests/check-window-rig.py >out/window-sizing/check.log 2>&1
        rc=$?; echo "$rc" >out/window-sizing/fresh.status; exit "$rc"')
trap 'docker rm -f "$container" >/dev/null' EXIT
status=$(docker wait "$container")
docker logs "$container"
test "$status" = 0
cat out/window-sizing/check.log
