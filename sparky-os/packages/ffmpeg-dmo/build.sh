#!/bin/bash
# Build one architecture from the successor recipe's single source package.
# Usage: build.sh SOURCE_DIR ARCH IMAGE REPO PREVIOUS ARCHIVE SIBLINGS WORK
# SIBLINGS lists the edition's dependency debs as /repo/... paths, excluding
# ffmpeg-dmo itself. PREVIOUS contains the corresponding architecture of +14.
# WORK retains the build tree for sample-based FATE and installed qualification.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
[ "$#" = 8 ] || { sed -n '2,7p' "$0" >&2; exit 2; }
SRC=$(realpath "$1") ARCH=$2 IMAGE=$3 REPO=$(realpath "$4")
PREVIOUS=$(realpath "$5") ARCHIVE=$(realpath "$6") SIBLINGS=$(realpath "$7")
WORK=$(realpath -m "$8")
case $ARCH in amd64) PLATFORM=linux/amd64; FLAGS=-b ;; i386) PLATFORM=linux/386; FLAGS=-B ;; *) exit 2 ;; esac
[ ! -e "$WORK" ] || [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 2; }
mkdir -p "$WORK"
sparky_provenance_init "$IMAGE" "$HERE/../../media/ffmpeg/stereo3d15"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:-ffmpeg}-build-$ARCH" --ulimit core=0 --cpus 4 --memory 12g --platform "$PLATFORM" \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e FLAGS="$FLAGS" -e OWNER="$(id -u):$(id -g)" \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -e SPARKY_LC_PREVIOUS_DIR=/previous -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/siblings.txt -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt \
    -v "$SRC":/src:ro -v "$REPO":/repo:ro -v "$PREVIOUS":/previous:ro -v "$ARCHIVE":/archive:ro \
    -v "$SIBLINGS":/siblings.txt:ro -v "$WORK":/work -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
    "$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh' > "$WORK/build.log" 2>&1
