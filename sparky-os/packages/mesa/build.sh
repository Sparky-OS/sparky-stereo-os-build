#!/bin/bash
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR
# SPARKY_MESA_BUILD_IMAGE must contain the source package's build dependencies.
set -euo pipefail
recipe=$(cd "$(dirname "$0")" && pwd)
work=$(mkdir -p "$1" && cd "$1" && pwd)
previous=$(cd "$2" && pwd)
source_dir=$(cd "$3" && pwd)
: "${SPARKY_MESA_BUILD_IMAGE:?image with the Mesa build dependencies}"
test -z "$(ls -A "$work")"
docker run --rm --cpus 4 --platform linux/amd64 --network none --user "$(id -u):$(id -g)" \
    -v "$work:/job" -v "$source_dir:/src:ro" -v "$previous:/prev:ro" \
    -v "$recipe/../..:/toolkit:ro" -v "$recipe:/tools:ro" \
    "$SPARKY_MESA_BUILD_IMAGE" bash /tools/prepare-source.sh /src /job/prepared
docker run --rm --cpus 4 --platform linux/amd64 --network none --user "$(id -u):$(id -g)" \
    -v "$work/prepared:/work" -v "$previous:/prev:ro" -v "$recipe/../..:/toolkit:ro" \
    -v "$recipe:/tools:ro" -e HOME=/work/home \
    "$SPARKY_MESA_BUILD_IMAGE" bash -c 'mkdir -p "$HOME"; bash /tools/build-in-container.sh > /work/build.log 2>&1'
