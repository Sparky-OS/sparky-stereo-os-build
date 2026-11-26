#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Sparky Stereo OS: okular 4:26.08.2-1+stereo3d1+lc1 from Debian testing's source (queue row 121), the edition's first okular.
# Usage: build-1.sh WORK SOURCE_DIR REPO_DIR ARCHIVE_DIR EXTRA_DIR PREVIOUS_SIBLINGS_FILE SIBLINGS_FILE
#   SOURCE_DIR: Debian's okular_26.08.2-1 source (source.sha256 names its files); EXTRA_DIR: .deb files installed before the
#   build dependencies; PREVIOUS_SIBLINGS_FILE: the published edition's packages as /repo paths; SIBLINGS_FILE: the same with
#   the packages this build depends on at newer versions (qt6-base +stereo3d25), as /repo or /extra paths.
# Run with the lane's DOCKER_HOST, SPARKY_BUILD_IMAGE and BUILD_NAME_PREFIX; the recipe's date is its last commit.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(realpath "$2")
REPO=$(realpath "$3")
ARCHIVE=$(realpath "$4")
EXTRA=$(realpath "$5")
PREVSIBS=$(realpath "$6")
SIBS=$(realpath "$7")
: "${SPARKY_BUILD_IMAGE:?an owned build image}" "${BUILD_NAME_PREFIX:?an owned container prefix}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
(cd "$SRC" && sha256sum --check --quiet "$HERE/source.sha256")
sparky_provenance_init "$SPARKY_BUILD_IMAGE"
docker run --pull=never --ulimit core=1 --name "${BUILD_NAME_PREFIX}-okular" --cpus 4 --platform linux/amd64 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_MIN_FREE_GIB=1 -e DPKG_DEB_THREADS_MAX=4 \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt \
    --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
    --mount "type=bind,src=$PREVSIBS,dst=/previous-siblings.txt,readonly" \
    --mount "type=bind,src=$SIBS,dst=/siblings.txt,readonly" \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$SRC,dst=/src,readonly" \
    --mount "type=bind,src=$EXTRA,dst=/extra,readonly" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" --mount "type=bind,src=$HERE,dst=/tools,readonly" \
    --mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$SPARKY_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container-1.sh >> /work/build.log 2>&1'
