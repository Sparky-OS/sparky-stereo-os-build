#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
. "$ROOT/sparky-os/repo/build-provenance.sh"
: "${DOCKER_HOST:?Use the lane Docker socket}"
IMAGE=${IMAGE:-pa19-rig:order19}
SOURCE_DATE_EPOCH=$(python3 "$ROOT/sparky-os/repo/reproducible.py" changelog /var/tmp/plasma-pa-virtual-streams/prepared/lc/source/debian/changelog)
export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS='the newest changelog of the prepared plasma-pa source'
sparky_provenance_init "$IMAGE" "$HERE"
exec_args=()
for ((i=0; i<${#SPARKY_PROV_ARGS[@]}; i++)); do
    if [[ ${SPARKY_PROV_ARGS[i]} == --mount ]]; then ((i+=1)); else exec_args+=("${SPARKY_PROV_ARGS[i]}"); fi
done
docker exec "${exec_args[@]}" -e SPARKY_PROVENANCE_REQUIRED=1 pa19-package \
    bash /lane/src/sparky-stereo-os-build/upstream/plasma-pa/build-inner.sh
