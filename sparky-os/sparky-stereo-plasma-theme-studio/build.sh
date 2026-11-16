#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
: "${DOCKER_HOST:?Use the lane Docker socket}"
: "${RIG_IMAGE:?Name the verified build and proof image}"
: "${BUILD_ROOT:?Choose an empty disposable build folder}"
: "${SPARKY_LC_ARCHIVE_CONFIG:?Name the signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?Choose the link gate scratch folder}"
: "${SPARKY_LC_SIBLINGS_FILE:?Name the frozen edition package list}"
mkdir -p "$BUILD_ROOT" "$SPARKY_LC_SCRATCH"
[ ! -e "$BUILD_ROOT/output" ] || { echo 'Use a fresh build folder' >&2; exit 1; }
source "$HERE/../repo/build-provenance.sh"
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init "$RIG_IMAGE" "$HERE"
docker run --rm --pull never --name "${CONTAINER_NAME:-theme-editor-build}" --platform linux/amd64 \
 --cpus 2 --ulimit core=0 --user "$(id -u):$(id -g)" --cap-add SYS_ADMIN \
 --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" \
 -v "${SPARKY_HTTPS_APT_HELPER:?}:/run/https-only-apt.sh:ro" \
 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
 -v "$ROOT:/source:ro" -v "$BUILD_ROOT:/build" \
 -v "$SPARKY_LC_ARCHIVE_CONFIG:$SPARKY_LC_ARCHIVE_CONFIG:ro" \
 -v "$SPARKY_LC_SIBLINGS_FILE:$SPARKY_LC_SIBLINGS_FILE:ro" \
 -v "$SPARKY_LC_SCRATCH:$SPARKY_LC_SCRATCH" \
 -v "${SPARKY_PUBLISHED_REPO:?}:$SPARKY_PUBLISHED_REPO:ro" \
 -v "${SPARKY_DMO_PUBLIC_KEYS:?}:$SPARKY_DMO_PUBLIC_KEYS:ro" \
 -e SPARKY_LC_ARCHIVE_CONFIG -e SPARKY_LC_SCRATCH -e SPARKY_LC_SIBLINGS_FILE \
 "$RIG_IMAGE" sh /source/sparky-os/theme-icon-editor/build-in-container.sh
