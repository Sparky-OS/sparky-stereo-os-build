#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Run against a disposable package container created with the mounts in the lane report.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
. "$ROOT/sparky-os/repo/build-provenance.sh"
IMAGE=${IMAGE:-pa19-rig:order19}
: "${DOCKER_HOST:?Use the lane Docker socket}"
sparky_provenance_init "$IMAGE" "$HERE"
docker exec "${SPARKY_PROV_ARGS[@]}" \
    -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
    -e LC_ALL=C.UTF-8 pa19-package python3 /lane/src/sparky-stereo-os-build/upstream/plasma-pa/make-source.py \
    /work19/plasma-pa_6.7.4-1.dsc /work19/prepared
