#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL2-or-later License
# The host side of the build: the facts only the host knows go into the container (build-provenance.sh), and the link gate gets
# its archive folder (sources.json with the public archives and the edition's published tree as file:/repo, and their keyrings).
# Usage: OUT=DIR SPARKY_LC_ARCHIVE_DIR=DIR REPO=PUBLISHED_TREE [IMAGE=...] bash build-in-container.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
. "$HERE/../../repo/build-provenance.sh"
OUT=${OUT:?Set OUT to the workspace output directory}
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive: see sparky-os/lean/archive.md}"
REPO=${REPO:?the published tree of the edition, mounted read-only at /repo}
IMAGE=${IMAGE:?a builder image with the packages named in debian/control}
SCRATCH=${SCRATCH:?a folder with room for the link gate}
mkdir -p "$OUT" "$SCRATCH"
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --ulimit core=1 --cpus 4 --user "$(id -u):$(id -g)" -e HOME="$SCRATCH/home" -e OUT="$OUT" -e JOBS=4 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH="$SCRATCH/link" \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$REPO":/repo:ro -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro \
	-v "$TREE":"$TREE" -v "$OUT":"$OUT" -v "$SCRATCH":"$SCRATCH" -v /etc/passwd:/etc/passwd:ro \
	"$IMAGE" sh -c "mkdir -p $SCRATCH/home $SCRATCH/link; git config --global --add safe.directory '*'; cd '$HERE' && bash ./build.sh"
