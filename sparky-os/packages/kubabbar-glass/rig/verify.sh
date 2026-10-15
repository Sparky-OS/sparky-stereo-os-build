#!/bin/bash
# Run after the fresh capture cases; verification never touches a live session.
set -euo pipefail
lane=$(cd "$(dirname "$0")/../.." && pwd)
[ -S "$lane/docker.sock" ] && export DOCKER_HOST="unix://$lane/docker.sock" || true
container=classic-look-verify
printf '%s\n' "$container" >> "$lane/.artifacts"
trap 'docker rm "$container" >/dev/null 2>&1 || true' EXIT
docker run --name "$container" --platform linux/amd64 --cpus 4 \
    --user "$(id -u):$(id -g)" --entrypoint /bin/sh \
    -v "$lane:$lane" -e CLASSIC_ROOT="$lane/theme" classic-look-rig:m1-oxygen -c '
    set -e
    for check in validate_assets check_frame_alpha check_compositor_alpha check_window_alpha check_depth check_caption; do
        python3 "$CLASSIC_ROOT/tools/$check.py" > "$CLASSIC_ROOT/evidence/verify-$check.log" 2>&1
    done
    '
