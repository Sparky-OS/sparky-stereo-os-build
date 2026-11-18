#!/bin/bash
# Sparky Stereo OS: build mesa 26.1.6-1+stereo3d26+lc1 from next-source-stereo3d26.sh's source through Lean Code, with the link and start
# gate against the +25 builds. Created by Daniel Ramos (Capitain Jack) 2026/11/18. Copyright 2026 under the GNU GPL3 License.
# Usage: build-stereo3d26.sh WORK SOURCE_DIR PREVIOUS_DIR ARCHIVE_DIR [PREVIOUS_SIBLINGS_FILE]
#   SOURCE_DIR: the folder next-source-stereo3d26.sh wrote, with mesa_26.1.6.orig.tar.xz beside the .dsc and the Debian tarball
#   PREVIOUS_DIR: the +stereo3d25+lc1 .deb files of mesa; ARCHIVE_DIR: the link gate's sources.json (sparky-os/lean/archive.md)
#   PREVIOUS_SIBLINGS_FILE: the published edition's other .deb files, one path per line as the container sees them (/repo/pool/...)
# SPARKY_MESA_BUILD_IMAGE must contain the source package's build dependencies; /repo is the signed tree for the gate.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
PREV=$(cd "$3" && pwd)
ARCHIVE=$(cd "$4" && pwd)
SIBS=${5:+$(readlink -f "$5")}
: "${SPARKY_MESA_BUILD_IMAGE:?image with the Mesa build dependencies}"
: "${SPARKY_REPO_DIR:?the signed published tree}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init "$SPARKY_MESA_BUILD_IMAGE"
docker run --rm --ulimit core=0 --name "${BUILD_NAME_PREFIX:-mesa-26}-mesa" --cpus "${SPARKY_BUILD_CPUS:-6}" --platform "${SPARKY_PLATFORM:-linux/amd64}" \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$ARCHIVE":/archive:ro \
	${SIBS:+-v "$SIBS":/previous-siblings.txt:ro -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt} \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$PREV":/prev:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$SPARKY_MESA_BUILD_IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-stereo3d26-in-container.sh >> /work/build.log 2>&1'
