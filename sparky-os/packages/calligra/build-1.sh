#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Sparky Stereo OS: calligra 1:26.08.0+dfsg-1+stereo3d1+lc1 from Debian testing's source (queue row 121), the edition's first calligra.
# Usage: build-1.sh WORK SOURCE_DIR REPO_DIR ARCHIVE_DIR EXTRA_DIR PREVIOUS_SIBLINGS_FILE SIBLINGS_FILE
#   SOURCE_DIR: Debian's calligra_26.08.0+dfsg-1 source (source.sha256 names its files); EXTRA_DIR: .deb files installed before the
#   build dependencies; PREVIOUS_SIBLINGS_FILE: the published edition's packages as /repo paths; SIBLINGS_FILE: the same with
#   the packages this build depends on at newer versions (qt6-base +stereo3d26) and its matching KWin, as /repo or /staged paths.
# Run with the lane's DOCKER_HOST, SPARKY_BUILD_IMAGE and BUILD_NAME_PREFIX; the recipe's date is its last commit.
# Set SPARKY_PKG_RESUME=1 to finish a checked source closure using its existing CMake build tree and source date.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(realpath "$2")
REPO=$(realpath "$3")
ARCHIVE=$(realpath "$4")
EXTRA=$(realpath "$5")
STAGED=$(dirname "$EXTRA")
PREVSIBS=$(realpath "$6")
SIBS=$(realpath "$7")
: "${SPARKY_BUILD_IMAGE:?an owned build image}" "${BUILD_NAME_PREFIX:?an owned container prefix}"
if [ "${SPARKY_PKG_RESUME:-0}" = 1 ]; then
    [ -f "$WORK/lc/source-closure.sha256" ] && [ -f "$WORK/lc/source/obj-x86_64-linux-gnu/CMakeCache.txt" ] ||
        { echo "$WORK holds no prepared Calligra build to resume" >&2; exit 1; }
    if compgen -G "$WORK/lc/*.deb" > /dev/null; then
        echo "$WORK/lc already contains binary packages; move them aside before resuming" >&2
        exit 1
    fi
    SOURCE_DATE_EPOCH=$(dpkg-parsechangelog -l "$WORK/lc/source/debian/changelog" -S Timestamp)
    export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS='the prepared Calligra changelog'
else
    [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
fi
(cd "$SRC" && sha256sum --check --quiet "$HERE/source.sha256")
sparky_provenance_init "$SPARKY_BUILD_IMAGE"
docker run --pull=never --ulimit core=1 --name "${BUILD_NAME_PREFIX}-calligra" --cpus 4 --platform linux/amd64 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_MIN_FREE_GIB=1 -e DPKG_DEB_THREADS_MAX=4 \
    -e "SPARKY_CALLIGRA_RESUME=${SPARKY_PKG_RESUME:-0}" \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt \
    --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
    --mount "type=bind,src=$PREVSIBS,dst=/previous-siblings.txt,readonly" \
    --mount "type=bind,src=$SIBS,dst=/siblings.txt,readonly" \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$SRC,dst=/src,readonly" \
    --mount "type=bind,src=$EXTRA,dst=/extra,readonly" \
    --mount "type=bind,src=$STAGED,dst=/staged,readonly" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" --mount "type=bind,src=$HERE,dst=/tools,readonly" \
    --mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$SPARKY_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container-1.sh >> /work/build.log 2>&1'
