#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
# Usage: IMAGE=BUILDER REPO=PUBLISHED_TREE SPARKY_LC_ARCHIVE_DIR=DIR
#        build-restart-to-firmware.sh WORK PREDECESSOR SIBLINGS PREVIOUS
# PREDECESSOR holds the staged plasma-workspace source closure. SIBLINGS
# supplies staged Screensavers and its package family. PREVIOUS holds the
# predecessor's binaries and the edition's APT policy for the link gate.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../repo/build-provenance.sh"
: "${IMAGE:?builder image}" "${REPO:?published repository}" "${SPARKY_LC_ARCHIVE_DIR:?archive configuration}"
work=$(mkdir -p "${1:?work directory}" && cd "$1" && pwd)
predecessor=$(cd "${2:?predecessor directory}" && pwd)
siblings=$(cd "${3:?sibling packages directory}" && pwd)
previous=$(cd "${4:?previous link gate control directory}" && pwd)
[ -z "$(ls -A "$work")" ] || { echo "$work is not empty" >&2; exit 1; }
sparky_provenance_init "$IMAGE" "$here"
container=${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}workspace-firmware
docker create --ulimit core=1 --name "$container" --cpus 4 --platform linux/amd64 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    --add-host repo.sparkyos.org:127.0.0.1 \
    "${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$work":/work -v "$predecessor":/predecessor:ro \
    -v "$siblings":/siblings:ro -v "$previous":/previous:ro -v "$REPO":/repo:ro \
    -v "$here/../..":/toolkit:ro -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
    -v "$here/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
    "$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /toolkit/packages/plasma-workspace/build-job-restart-to-firmware.sh >/work/job.log 2>&1' \
    >"$work/container.id"
docker start -a "$container"
