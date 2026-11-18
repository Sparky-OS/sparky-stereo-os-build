#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Usage: build.sh EMPTY_WORK LC_SOURCE_DIR PREVIOUS_DEBS_DIR
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
. "$ROOT/sparky-os/repo/build-provenance.sh"
. "$HERE/common.sh"
: "${SPARKY_REPO_DIR:?signed edition repository, mounted read-only at /repo}"
: "${SPARKY_LC_ARCHIVE_DIR:?sources.json and its public keyrings, mounted read-only at /archive}"
WORK=$(mkdir -p "${1:?empty work directory}" && cd "$1" && pwd)
SRC=$(cd "${2:?directory holding the prepared LC descriptor and tarballs}" && pwd)
PREV=$(cd "${3:?previous binary packages}" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
SOURCE_DATE_EPOCH=$(python3 "$HERE/source-epoch.py" "$SRC/plasma-pa_6.7.4-1+stereo3d3+lc1.debian.tar.xz")
export SOURCE_DATE_EPOCH SPARKY_PROVENANCE_REQUIRED=1 SPARKY_SOURCE_DATE_BASIS='the newest changelog of the supplied plasma-pa LC source'
sparky_provenance_init "$IMAGE" "$HERE"
# Edition packages this one depends on that are staged and not yet in the signed repository (sparky-stereo-audio, ORDER 631): their paths, as seen in /previous, one per line in PREVIOUS_DEBS_DIR/siblings.txt
SIBLINGS=()
[ -f "$PREV/siblings.txt" ] && SIBLINGS=(-e SPARKY_LC_SIBLINGS_FILE=/previous/siblings.txt)
docker run --rm --name "${CONTAINER_NAME:-plasma-pa-build}" --platform linux/amd64 --ulimit core=0 --cpus "$CPUS" \
    --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" "${SIBLINGS[@]}" \
    -e BUILD_UID="$BUILD_UID" -e BUILD_GID="$BUILD_GID" -e PYTHONDONTWRITEBYTECODE=1 -e BUILD_THREADS="$CPUS" \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -e SPARKY_LC_PREVIOUS_DIR=/previous \
    -v "$WORK:/work" -v "$SRC:/source-input:ro" -v "$PREV:/previous:ro" -v "$ROOT:/build-tree:ro" \
    -v "$SPARKY_REPO_DIR:/repo:ro" -v "$SPARKY_LC_ARCHIVE_DIR:/archive:ro" \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
    -v "$ROOT/tools/https-only-apt.sh:/run/https-only-apt.sh:ro" \
    "$IMAGE" bash /build-tree/sparky-os/upstream/plasma-pa/build-inner.sh
