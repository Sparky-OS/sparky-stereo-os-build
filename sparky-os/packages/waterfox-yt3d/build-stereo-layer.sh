#!/bin/bash
# Sparky Stereo OS: libstereo-policy 1.13.0 (and the whole stereo-layer cohort at 1.13.0-1+lc1) through Lean Code (ORDER 193, 6a-2).
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# The source is the release tag of the stereo-layer clone (its own debian/ directory is the recipe); the yt3d site mark reader is in
# libstereo-policy 1.13.0 (docs/yt3d.md). The cohort is rebuilt whole because libstereo-layer1 depends on libstereo-policy1 of the same build.
# Usage: SPARKY_LC_ARCHIVE_DIR=ARCHIVE build-stereo-layer.sh WORK PUB PREVIOUS_DIR FORK_CLONE
#   ARCHIVE: the link gate's folder (sources.json and its public keyrings, sparky-os/lean/archive.md), mounted at /archive;
#   WORK: an empty job folder; PUB: the signed tree the build resolves its dependencies from; PREVIOUS_DIR: the earlier +lc1 .deb
#   files of the package (the link and start gate compares against them); FORK_CLONE: the stereo-layer clone with tag release-1.13.0.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate folder (mounted at /archive: sources.json and its public keyrings), see sparky-os/lean/archive.md}"
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd -P)
PUB=$(cd "$2" && pwd -P)
PREV=$(cd "$3" && pwd -P)
FORK=$(cd "$4" && pwd -P)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init sparky-lc-migration:20261020
docker run --rm --name w196-stereo-layer --cpus "${CPUS:-8}" --memory 32g --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -e JOBS="${CPUS:-8}" \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$WORK":/work -v "$PUB":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$FORK":/fork:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	sparky-lc-migration:20261020 bash -c 'sh /run/https-only-apt.sh && bash /toolkit/packages/waterfox-yt3d/build-stereo-layer-in-container.sh > /work/build.log 2>&1'
