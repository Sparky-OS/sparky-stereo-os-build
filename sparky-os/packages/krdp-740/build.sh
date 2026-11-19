#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../repo/build-provenance.sh"
export SPARKY_PROVENANCE_REQUIRED=1
export DOCKER_HOST="${FH740_DOCKER_HOST:?set the lane Docker socket}"
sparky_provenance_init "${FH740_BUILD_IMAGE:?set the prepared pair build image}" "$here"
docker run --name fh740h-krdp-package --pull=never --platform linux/amd64 --ulimit core=0 --cpus=4 \
 --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" \
 --mount type=bind,source="${FH740_WORKSPACE:?set the isolated work directory}",target=/work \
 --mount type=bind,source="${FH740_ARCHIVE:?set the published predecessor archive}",target=/repo,readonly \
 --mount type=bind,source="${FH740_CA_BUNDLE:?set the CA bundle}",target=/run/host-ca.crt,readonly \
 --mount type=bind,source="${FH740_HTTPS_HELPER:?set the HTTPS-only apt helper}",target=/run/https-only-apt.sh,readonly \
 "$FH740_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh; bash /work/src/sparky-stereo-os-build/sparky-os/packages/krdp-740/build-in-container.sh'
