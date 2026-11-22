#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/22
# Builds kf6-kiconthemes 6.32.0-1+stereo3dSTEP+lc1 with build-job-stereo3dSTEP.sh: STEP 3 (queue row 77 milestone 2,
# the default) from the staged +stereo3d2, or STEP 2 (milestone 1) from the round's +stereo3d1.
# usage: build.sh WORK PREDECESSOR_DIR PUBLISHED_TREE ARCHIVE_DIR
#   WORK            empty scratch folder for the build
#   PREDECESSOR_DIR folder holding the predecessor's .dsc and its files (+stereo3d2 for STEP 3, +stereo3d1 for STEP 2)
#   PUBLISHED_TREE  the edition's published repository (dists/ and pool/)
#   ARCHIVE_DIR     the link gate's archive: sources.json and the keyrings it names
# IMAGE names the builder image (default sparky-lc-migration:20261020); DEBIAN_SNAPSHOT the Debian instant.
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${1:?work folder}; PREV=${2:?predecessor folder}; REPO=${3:?published tree}; ARCHIVE=${4:?archive folder}
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT:-20261121T150000Z}
STEP=${STEP:-3}
[[ $STEP =~ ^[23]$ ]] || { echo "STEP is 2 or 3" >&2; exit 2; }
NAME=${CONTAINER_NAME:-kiconthemes-stereo3d$STEP-build}
[[ $DEBIAN_SNAPSHOT =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "DEBIAN_SNAPSHOT must be an instant such as 20261121T150000Z" >&2; exit 2; }
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 2; }
# shellcheck source=../../repo/build-provenance.sh
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$IMAGE" "$HERE"
docker run --name "$NAME" --ulimit core=1 --cpus 4 --platform linux/amd64 --pull=never \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e DEBIAN_SNAPSHOT="$DEBIAN_SNAPSHOT" -e STEP="$STEP" \
	--mount "type=bind,src=$WORK,dst=/work" \
	--mount "type=bind,src=$PREV,dst=/predecessor,readonly" \
	--mount "type=bind,src=$REPO,dst=/repo,readonly" \
	--mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
	--mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" \
	--mount "type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly" \
	--mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	"$IMAGE" bash -c 'set -e
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
printf "Types: deb\nURIs: https://snapshot.debian.org/archive/debian/%s\nSuites: testing\nComponents: main contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\nCheck-Valid-Until: no\n" "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list.d/debian.sources
printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /repo/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/edition.sources
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
sh /run/https-only-apt.sh
bash /toolkit/packages/kf6-kiconthemes/build-job-stereo3d$STEP.sh > /work/job.log 2>&1'
