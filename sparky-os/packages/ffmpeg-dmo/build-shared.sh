#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
[ "$#" = 3 ] || { echo 'Usage: build.sh IMAGE WORK PUBLISHED_REPOSITORY' >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(realpath "$2")
REPO=$(realpath "$3")
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$1" "$HERE"
docker run --name "${SPARKY_CONTAINER_PREFIX:-ffmpeg}-ffmpeg-package" --pull=never \
    --platform linux/amd64 --cpus 4 --ulimit core=0 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e DEB_BUILD_OPTIONS=parallel=4 -e SPARKY_BUILD_RESUME="${SPARKY_BUILD_RESUME:-0}" \
    -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
    -e SPARKY_LC_ARCHIVE_CONFIG=/recipe/archive-sources.json -e SPARKY_LC_SCRATCH=/work/link-ffmpeg \
    -e SPARKY_LC_SIBLINGS_FILE=/work/siblings-ffmpeg.txt -e SPARKY_LC_PREVIOUS_DIR=/work/previous-ffmpeg \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$HERE,dst=/recipe,readonly" \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$1" bash -c 'set -eu; ulimit -c 0; sh /run/https-only-apt.sh; export DEBIAN_FRONTEND=noninteractive; apt-get -y --no-install-recommends install /repo/pool/main/n/nvidia-graphics-drivers/libnvidia-glvkspirv_580.196.07-1+sparky3+lc1_amd64.deb /work/x265-build/libx265-219_*_amd64.deb /work/x265-build/libx265-dev_*_amd64.deb; apt-get -y --no-install-recommends build-dep /work/ffmpeg-build/ffmpeg-dmo-9.0.2; id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder; cd /work/ffmpeg-build/ffmpeg-dmo-9.0.2; if [ "$SPARKY_BUILD_RESUME" = 1 ]; then runuser -u builder -- dpkg-buildpackage -nc -b -us -uc -j4; else runuser -u builder -- dpkg-buildpackage -us -uc -sa -j4; fi'
