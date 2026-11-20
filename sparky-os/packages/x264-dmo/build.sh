#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
[ "$#" = 3 ] || { echo 'Usage: build.sh IMAGE WORK PUBLISHED_REPOSITORY' >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(realpath "$2")
REPO=$(realpath "$3")
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$1" "$HERE"
docker run --name "${SPARKY_CONTAINER_PREFIX:-x264}-x264-package" --pull=never \
    --platform linux/amd64 --cpus 4 --ulimit core=1 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e DEB_BUILD_OPTIONS=parallel=4 \
    -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
    -e SPARKY_LC_ARCHIVE_CONFIG=/recipe/archive-sources.json -e SPARKY_LC_SCRATCH=/work/link-x264 \
    -e SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt -e SPARKY_LC_PREVIOUS_DIR=/work/previous-x264 \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$HERE,dst=/recipe,readonly" \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$1" bash -c 'set -eu; sh /run/https-only-apt.sh; export DEBIAN_FRONTEND=noninteractive; apt-get -y --no-install-recommends build-dep /work/x264-build/x264-dmo-0.165.3222+gitb35605a; id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder; cd /work/x264-build/x264-dmo-0.165.3222+gitb35605a; runuser -u builder -- dpkg-buildpackage -us -uc -sa -j4; cd ..; PYTHONPATH=$(pwd)/x264-dmo-0.165.3222+gitb35605a/debian/sparky-lean-toolkit python3 -m lean.release check-debs ./*.deb'
