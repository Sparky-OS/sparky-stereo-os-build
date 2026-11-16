#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Usage: package.sh EMPTY_WORK DEBIAN_SOURCE_DIR
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
. "$ROOT/sparky-os/repo/build-provenance.sh"
. "$HERE/common.sh"
WORK=$(mkdir -p "${1:?empty work directory}" && cd "$1" && pwd)
SRC=$(cd "${2:?directory holding Debian plasma-pa_6.7.4-1.dsc and its archives}" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --name "${CONTAINER_NAME:-plasma-pa-source}" --platform linux/amd64 --ulimit core=0 --cpus "$CPUS" \
    "${SPARKY_PROV_ARGS[@]}" \
    -e BUILD_UID="$BUILD_UID" -e BUILD_GID="$BUILD_GID" -e PYTHONDONTWRITEBYTECODE=1 \
    -v "$WORK:/work" -v "$SRC:/source-input:ro" -v "$ROOT:/build-tree:ro" \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
    -v "$ROOT/tools/https-only-apt.sh:/run/https-only-apt.sh:ro" \
    "$IMAGE" bash /build-tree/sparky-os/upstream/plasma-pa/source-inner.sh
