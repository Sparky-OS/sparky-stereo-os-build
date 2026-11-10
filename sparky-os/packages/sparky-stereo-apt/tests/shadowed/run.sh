#!/bin/bash
# ORDER 458: one proof container per mode: run.sh MODE   (red | green | manual | needed | fresh; container mlt-458-MODE, removed at the end)
# Paths come from the environment: NEW (folder with the built sparky-stereo-apt), REPO (a published tree, default /K3D/sparky-repo-r1107a),
# CACHE (a folder that keeps the downloaded .debs between runs), EVID (where the log goes). Needs the https-only helper of /K3D/partners.
set -u
MODE=$1
T=$(cd "$(dirname "$0")" && pwd)
: "${NEW:?folder with the new package}" "${CACHE:?folder for the .deb cache}" "${EVID:?evidence folder}" "${IMAGE:?an amd64 forky image with ca-certificates}"
REPO=${REPO:-/K3D/sparky-repo-r1107a}
HELPER=${HELPER:-/K3D/partners/https-only-apt.sh}
mkdir -p "$EVID" "$CACHE/partial"
docker run --rm --name "mlt-458-$MODE" --cpus 2 --ulimit core=0 --platform linux/amd64 \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HELPER":/run/https-only-apt.sh:ro \
	-v "$REPO":/repo:ro -v "$NEW":/new:ro -v "$T":/t:ro -v "$CACHE":/var/cache/apt/archives "$IMAGE" \
	bash /t/inside.sh "$MODE" 2>&1 | tee "$EVID/$MODE.log"
exit "${PIPESTATUS[0]}"
