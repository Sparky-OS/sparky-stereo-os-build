#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: build-26.sh WORK SOURCE_DIR PREVIOUS_DIR REPO_DIR ARCHIVE_DIR EXTRA_DIR PREVIOUS_SIBLINGS_FILE
#   PREVIOUS_DIR: the milestone 1 +25 binaries; PREVIOUS_SIBLINGS_FILE: only edition packages the build needs that are not
#   published yet, an empty file for +26 (the published ones reach the gate through ARCHIVE_DIR; a list holding the published
#   qt6-base binaries stops the gate: "conflicting supplied package: libqt6core6t64").
# Run with the lane's DOCKER_HOST, SPARKY_BUILD_IMAGE, BUILD_NAME_PREFIX and recipe SOURCE_DATE_EPOCH.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(realpath "$2")
PREV=$(realpath "$3")
REPO=$(realpath "$4")
ARCHIVE=$(realpath "$5")
EXTRA=$(realpath "$6")
STAGED=$(dirname "$EXTRA")
SIBS=$(realpath "$7")
: "${SPARKY_BUILD_IMAGE:?an owned build image}" "${BUILD_NAME_PREFIX:?an owned container prefix}"
if [ "${SPARKY_PKG_RESUME:-0}" = 1 ]; then
    [ -f "$WORK/lc/source-closure.sha256" ] && [ -d "$WORK/lc/source/obj-x86_64-linux-gnu" ]
else
    [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
fi
sparky_provenance_init "$SPARKY_BUILD_IMAGE"
docker run --pull=never --ulimit core=1 --name "${BUILD_NAME_PREFIX}-qt6-base" --cpus 4 --platform linux/amd64 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_MIN_FREE_GIB=1 -e DPKG_DEB_THREADS_MAX=4 -e SPARKY_QT_RESUME="${SPARKY_PKG_RESUME:-0}" \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt \
    --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
    --mount "type=bind,src=$SIBS,dst=/previous-siblings.txt,readonly" \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$SRC,dst=/src,readonly" \
    --mount "type=bind,src=$EXTRA,dst=/extra,readonly" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$STAGED,dst=/staged,readonly" \
    --mount "type=bind,src=$PREV,dst=/prev,readonly" --mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" \
    --mount "type=bind,src=$HERE,dst=/tools,readonly" \
    --mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$SPARKY_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container-26.sh >> /work/build.log 2>&1'
