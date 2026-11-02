#!/bin/bash
# SPDX-License-Identifier: MIT
# Build as the ordinary container user with the cohort's development packages.
set -euo pipefail
: "${SPARKY_LC_ARCHIVE_CONFIG:?signed archive configuration for the link gate}"
: "${SPARKY_LC_SCRATCH:?private link-gate scratch directory}"
HERE=$(cd "$(dirname "$0")" && pwd)
: "${WORK:?empty build directory}"
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
VERSION=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
# A neutral directory keeps dch from renaming the native source during prepare.
SOURCE=$WORK/source
python3 "$HERE/../../../tools/copy-recipe.py" "$HERE" "$SOURCE"
export PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$SOURCE" "$VERSION+lc1" --toolkit "$HERE/../.."
export DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
(cd "$SOURCE" && dpkg-buildpackage -us -uc -j4)
