#!/bin/bash
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD=$(cd "$HERE/../.." && pwd)
: "${SPARKY_BUILDER_IMAGE:?Set the prepared Debian testing builder image}"
: "${SPIRULA_SOURCE:?Set the clean edition fork checkout}"
: "${OUT:?Set an owned empty output folder}"
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set the public signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?Set the disposable archive-gate workspace}"
: "${SPARKY_BUILD_CONTAINER:?Set an individually named build container}"
: "${SPARKY_HTTPS_APT_HELPER:?Set the shared HTTPS-only apt helper}"
: "${SPARKY_HOST_CA:?Set the public host CA bundle}"
mkdir -p "$OUT" "$SPARKY_LC_SCRATCH"
export SPARKY_PROVENANCE_REQUIRED=1
. "$BUILD/repo/build-provenance.sh"
sparky_provenance_init "$SPARKY_BUILDER_IMAGE" "$HERE"
docker run --name "$SPARKY_BUILD_CONTAINER" --platform linux/amd64 --user "$(id -u):$(id -g)" --ulimit core=0 --cpus 4 \
    --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e SPIRULA_SOURCE -e OUT -e SPARKY_LC_ARCHIVE_CONFIG -e SPARKY_LC_SCRATCH -e SPARKY_LC_SIBLINGS_FILE \
    -e SPARKY_LC_MIN_FREE_GIB=2 -e SPARKY_LC_ROOT_MIN_FREE_GIB=1 -e JOBS=4 \
    --mount "type=bind,src=$SPIRULA_SOURCE,dst=$SPIRULA_SOURCE,readonly" \
    --mount "type=bind,src=$BUILD,dst=$BUILD,readonly" --mount "type=bind,src=$OUT,dst=$OUT" \
    --mount "type=bind,src=$SPARKY_LC_SCRATCH,dst=$SPARKY_LC_SCRATCH" \
    --mount "type=bind,src=$SPARKY_HTTPS_APT_HELPER,dst=/run/https-only-apt.sh,readonly" \
    --mount "type=bind,src=$SPARKY_HOST_CA,dst=/run/host-ca.crt,readonly" \
    "$@" "$SPARKY_BUILDER_IMAGE" bash -c 'set -euo pipefail; export HTTPS_ONLY_APT_CONF="$OUT/https-only-apt.conf"; sh /run/https-only-apt.sh; export APT_CONFIG="$HTTPS_ONLY_APT_CONF"; exec "$1/build.sh"' bash "$HERE"
