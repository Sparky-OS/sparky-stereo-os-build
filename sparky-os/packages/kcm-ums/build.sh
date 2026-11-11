#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/11
# Copyright 2026 under the GNU GPL3 License
# Build the tracked plain native source, then prepare and qualify its lc1 release source.
# Usage: build.sh EMPTY_WORK PREVIOUS_DEBS
# Set SPARKY_REPO_DIR and SPARKY_LC_ARCHIVE_DIR (sources.json and public keyrings).
# IMAGE defaults to the edition's migration image; SPARKY_CONTAINER_PREFIX names isolated jobs.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
: "${SPARKY_REPO_DIR:?set the published repository directory}"
: "${SPARKY_LC_ARCHIVE_DIR:?set the public archive configuration directory}"
WORK=$(mkdir -p "${1:?empty work directory}" && realpath "$1")
PREVIOUS=$(realpath "${2:?previous package directory}")
REPO=$(realpath "$SPARKY_REPO_DIR")
ARCHIVE=$(realpath "$SPARKY_LC_ARCHIVE_DIR")
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ -f "$ARCHIVE/sources.json" ]
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
SOURCE_DATE_EPOCH=$(python3 "$HERE/../../repo/reproducible.py" changelog "$HERE/debian/changelog")
export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS='the newest kcm-ums changelog entry'
sparky_provenance_init "$IMAGE"
python3 "$HERE/../../../tools/copy-recipe.py" "$HERE" "$WORK/plain/source"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}kcm-ums-build" \
 --platform linux/amd64 --cpus 4 --ulimit core=0 \
 --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json \
 -e SPARKY_LC_SCRATCH=/work/link-scratch -e SPARKY_LC_PREVIOUS_DIR=/previous \
 -e "OWNER=$(id -u):$(id -g)" -v "$WORK:/work" -v "$PREVIOUS:/previous:ro" \
 -v "$REPO:/repo:ro" -v "$ARCHIVE:/archive:ro" -v "$HERE/../..:/toolkit:ro" -v "$HERE:/tools:ro" \
 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
 -v "$HERE/../../../tools/https-only-apt.sh:/run/https-only-apt.sh:ro" \
 "$IMAGE" bash /tools/build-in-container.sh
