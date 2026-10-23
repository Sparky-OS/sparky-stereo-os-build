#!/bin/bash
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
# Run after the amd64 cohort; both builds consume the already staged exact .dsc.
set -euo pipefail
: "${SPARKY_PACKAGE_WORK:?Set owned package scratch}"
: "${SPARKY_I386_IMAGE:?Set the i386 package build image}"
: "${SPARKY_TEST_PREFIX:?Set an owned prefix}"
here=$(cd "$(dirname "$0")" && pwd)
export SPARKY_PACKAGE_IMAGE=$SPARKY_I386_IMAGE BINARY_ONLY=-B
for package in libplacebo-dmo ffmpeg-dmo; do
 SOURCE_DSC=$(find "$SPARKY_PACKAGE_WORK/out/$package" -maxdepth 1 -name '*.dsc' -printf '%f\n')
 [ "$(printf '%s\n' "$SOURCE_DSC" | wc -l)" = 1 ]
 export SOURCE_DSC
 bash "$here/run-build.sh" "$package" -i386
 python3 "$here/stage.py" "$SPARKY_PACKAGE_WORK" "$package" --job "$package-i386"
done
python3 "$here/cohort.py" "$SPARKY_PACKAGE_WORK" --finish
