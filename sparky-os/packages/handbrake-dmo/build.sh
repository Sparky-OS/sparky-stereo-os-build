#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the prepared descriptor with its retained contrib archives.
set -euo pipefail
[ "$#" = 3 ] || { echo 'Usage: build.sh IMAGE WORK PUBLISHED_REPOSITORY' >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(realpath "$2")
REPO=$(realpath "$3")
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$1" "$HERE"
docker run --name "${SPARKY_CONTAINER_PREFIX:-handbrake}-package" --pull=never \
    --platform linux/amd64 --cpus 4 --ulimit core=0 --network none \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    --user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" \
    -e DEB_BUILD_OPTIONS=parallel=4 \
    -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
    --mount "type=bind,src=$WORK,dst=/work" \
    --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    "$1" bash -c 'ulimit -c 0; cd /work/source/handbrake-dmo-1.11.2; dpkg-buildpackage -us -uc -sa -j4'
