#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../repo/build-provenance.sh"
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init fh740h-linux:3 "$here"
docker run --name fh740h-krdp-package --pull=never --platform linux/amd64 --ulimit core=0 --cpus=4 \
 --cap-add SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" \
 --mount type=bind,source=/var/tmp/flat-headset-hevc-740,target=/work \
 --mount type=bind,source=/K3D/sparky-repo-r1117a,target=/repo,readonly \
 --mount type=bind,source=/etc/ssl/certs/ca-certificates.crt,target=/run/host-ca.crt,readonly \
 --mount type=bind,source=/K3D/partners/https-only-apt.sh,target=/run/https-only-apt.sh,readonly \
 fh740h-linux:3 bash -c 'sh /run/https-only-apt.sh; bash /work/src/sparky-stereo-os-build/sparky-os/packages/krdp-740/build-in-container.sh'
