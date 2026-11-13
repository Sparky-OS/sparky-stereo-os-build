#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# ORDER 518 candidate; the published source, edition Lean Code and header gate.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd -P)
REPO=$(cd "$2" && pwd -P)
ARCHIVE=$(cd "$3" && pwd -P)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK must be empty" >&2; exit 2; }
sparky_provenance_init sparky-lc-migration:20261020
docker run --rm --name qt-518-package --cpus 4 --platform linux/amd64 --ulimit core=0 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    --add-host repo.sparkyos.org:192.168.0.60 "${SPARKY_PROV_ARGS[@]}" \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -v "$WORK":/work -v "$REPO":/repo:ro -v "$ARCHIVE":/archive:ro \
    -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
    -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
    -v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
    sparky-lc-migration:20261020 bash -c 'sh /run/https-only-apt.sh && bash /tools/build-518-in-container.sh' \
    > "$WORK/build.log" 2>&1
bash "$HERE/test.sh" "$WORK/lc" "$WORK/header-test"
