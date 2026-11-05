#!/bin/bash
# Sparky Stereo OS: plasmatube 26.08.1-1+stereo3d5+lc1, the +stereo3d4 plain source plus patch 0006 (the yt3d keywords read by
# libstereo-policy 1.13), built with Lean Code (ORDER 193, 6a-2).
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Usage: SPARKY_LC_ARCHIVE_DIR=ARCHIVE build-plasmatube.sh WORK PUB PREVIOUS_DIR SOURCE_DIR EXTRA_DIR
#   ARCHIVE: the link gate folder (sources.json and its public keyrings, sparky-os/lean/archive.md), mounted at /archive;
#   WORK: an empty job folder; PUB: the signed tree; PREVIOUS_DIR: the earlier +lc1 .deb files of plasmatube;
#   SOURCE_DIR: the plain plasmatube_26.08.1-1+stereo3d4 .dsc, debian.tar.xz and the orig tarball;
#   EXTRA_DIR: the libstereo-policy1 and libstereo-policy-dev 1.13.0-1+lc1 .deb files (build-stereo-layer.sh), installed before the
#   build dependencies and given to the link gate as the current siblings.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
. "$HERE/../../repo/build-provenance.sh"
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate folder (mounted at /archive: sources.json and its public keyrings), see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd -P)
PUB=$(cd "$2" && pwd -P)
PREV=$(cd "$3" && pwd -P)
SRC=$(cd "$4" && pwd -P)
EXTRA=$(cd "$5" && pwd -P)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init sparky-lc-migration:20261020
docker run --rm --name w196-plasmatube --cpus "${CPUS:-8}" --memory 16g --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -e JOBS="${CPUS:-8}" \
	-v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$WORK":/work -v "$SRC":/src:ro -v "$EXTRA":/extra:ro -v "$PUB":/repo:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE/plasmatube":/recipe:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	sparky-lc-migration:20261020 bash -c 'sh /run/https-only-apt.sh && bash /toolkit/packages/waterfox-yt3d/build-plasmatube-in-container.sh > /work/build.log 2>&1'
