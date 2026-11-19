#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../repo/build-provenance.sh"
export SPARKY_PROVENANCE_REQUIRED=1
export DOCKER_HOST="${PV24_DOCKER_HOST:?set the lane Docker socket}"
sparky_provenance_init "${PV24_BUILD_IMAGE:?set the prepared UMS build image}" "$here"
if [[ ${PV24_PHASE:-build} = build && ${PV24_NETWORK:-none} != none ]]; then echo "UMS tests require network none" >&2; exit 1; fi
docker run --name pv24-ums-package --pull=never --platform linux/amd64 --ulimit core=0 --cpus=4 --network "${PV24_NETWORK:-none}" \
 --hostname pv24-ums --add-host pv24-ums:127.0.0.1 --add-host repo.sparkyos.org:192.168.0.60 --cap-add NET_ADMIN --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" \
 --mount type=bind,source="${PV24_WORKSPACE:?set the isolated work directory}",target=/work \
 --mount type=bind,source="${PV24_UMS_JOB:?set the isolated package scratch}",target=/work/linux/ums-package \
 --mount type=bind,source="${PV24_ARCHIVE:?set the published archive}",target=/repo,readonly \
 -e PV24_PHASE="${PV24_PHASE:-build}" \
 --mount type=bind,source="${PV24_CA_BUNDLE:?set the CA bundle}",target=/run/host-ca.crt,readonly \
 --mount type=bind,source="${PV24_HTTPS_HELPER:?set the HTTPS-only apt helper}",target=/run/https-only-apt.sh,readonly \
 "$PV24_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh; bash /work/src/sparky-stereo-os-build/sparky-os/packages/ums-phone/build-in-container.sh'
