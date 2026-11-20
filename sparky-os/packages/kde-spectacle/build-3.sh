#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
# Usage: build-3.sh WORK SOURCE_DIR PREVIOUS_DIR REPO_DIR ARCHIVE_DIR SIBLINGS_FILE
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
: "${DOCKER_HOST:?point to the owned build daemon}" "${SPARKY_BUILD_IMAGE:?an owned image}" "${BUILD_NAME_PREFIX:?an owned prefix}"
WORK=$(realpath -m "$1"); SRC=$(realpath "$2"); PREV=$(realpath "$3"); REPO=$(realpath "$4"); ARCHIVE=$(realpath "$5"); SIBS=$(realpath "$6")
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK must be empty" >&2; exit 1; }
sparky_provenance_init "$SPARKY_BUILD_IMAGE"
export DOCKER_HOST
docker run --name "${BUILD_NAME_PREFIX}-spectacle" --pull=never --ulimit core=1 --cpus 4 --platform linux/amd64 \
 --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" -e DEB_BUILD_OPTIONS=parallel=4 -e DPKG_DEB_THREADS_MAX=4 -e CMAKE_BUILD_PARALLEL_LEVEL=4 \
 -e QT_QPA_PLATFORM=offscreen -e LANG=C.UTF-8 -e 'DEBFULLNAME=Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
 -e SPARKY_LC_ARCHIVE_CONFIG=/archive/archive-config.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
 -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/siblings.txt -e SPARKY_LC_PREVIOUS_DIR=/prev -e SPARKY_LC_MIN_FREE_GIB=1 \
 --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" --mount "type=bind,src=$SIBS,dst=/siblings.txt,readonly" \
 --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$SRC,dst=/src,readonly" \
 --mount "type=bind,src=$PREV,dst=/prev,readonly" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
 --mount "type=bind,src=$HERE/../../..,dst=/machinery,readonly" --mount "type=bind,src=$HERE,dst=/tools,readonly" \
 --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
 --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
 "$SPARKY_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh && cp /run/host-ca.crt /etc/ssl/certs/ca-certificates.crt && bash /tools/build-in-container-3.sh'
