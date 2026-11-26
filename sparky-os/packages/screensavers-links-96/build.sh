#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Queue row 96: builds one of the four packages that gain the link to the Screensavers page (build-job.sh, jobs.tsv).
# Usage: IMAGE=BUILDER SPARKY_LC_ARCHIVE_DIR=DIR REPO=PUBLISHED_TREE build.sh PROJECT WORK PREDECESSOR_DIR SIBLINGS_DIR PREVIOUS_DIR
#   PREDECESSOR_DIR  the folder holding the predecessor's +lc1 .dsc with every file it names and its +lc1 .deb files
#   SIBLINGS_DIR     the staged sparky-stereo-screensavers and gl-stereo packages (the new Depends, not published yet)
#                    and the edition's policy package sparky-stereo-apt, whose pins the link gate then applies
#   PREVIOUS_DIR     the predecessor's +lc1 .deb files with the same policy package beside them: the gate qualifies the
#                    previous build too, and an exact dependency on our Qt is solvable only under the edition's pins
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
PROJECT=${1:?project} WORK=$(mkdir -p "$2" && cd "$2" && pwd) PRED=$(cd "$3" && pwd) SIB=$(cd "$4" && pwd) PREV=$(cd "$5" && pwd)
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate (sparky-os/lean/archive.md)}" "${REPO:?the published tree}" "${IMAGE:?a builder image}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init "$IMAGE" "$HERE"
docker run --ulimit core=1 --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}links-$PROJECT" --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e PROJECT="$PROJECT" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$WORK":/work -v "$PRED":/predecessor:ro -v "$SIB":/siblings:ro -v "$PREV":/previous:ro \
	-v "$REPO":/repo:ro -v "$HERE/../..":/toolkit:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /toolkit/packages/screensavers-links-96/build-job.sh > /work/job.log 2>&1'
