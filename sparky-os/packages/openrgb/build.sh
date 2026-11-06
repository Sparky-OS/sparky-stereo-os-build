#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Run as the build user in a disposable container with the cohort build dependencies.
# ORIG is the published release_1.0 Files-Excluded orig archive, mounted read-only.
# WORK must be empty; source, binaries and Lean Code companions stay there for review.
set -euo pipefail
: "${SPARKY_LC_ARCHIVE_CONFIG:?signed archive configuration for the link gate}"
: "${SPARKY_LC_SCRATCH:?private link-gate scratch directory}"
HERE=$(cd "$(dirname "$0")" && pwd)
# The source is dated by its recipe, never by the clock (ORDER 421b): SOURCE_DATE_EPOCH, else the last commit touching this folder.
REPRO=$HERE/../../repo/reproducible.py
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" epoch "$HERE")}
export SOURCE_DATE_EPOCH
: "${ORIG:?published openrgb_1.0+ds.orig.tar.xz}"
: "${WORK:?empty build directory}"
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
cp "$ORIG" "$WORK/openrgb_1.0+ds.orig.tar.xz"
tar -xf "$ORIG" -C "$WORK"
SOURCE=$WORK/openrgb-1.0+ds
[ -d "$SOURCE" ]
# The release archive has no Debian packaging; this recipe owns it.
python3 "$HERE/../../../tools/copy-recipe.py" "$HERE/debian" "$SOURCE/debian"
VERSION=$(dpkg-parsechangelog -l "$SOURCE/debian/changelog" -S Version)
export PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$SOURCE" "$VERSION+lc1" --toolkit "$HERE/../.."
export DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" "$SOURCE"
(cd "$SOURCE" && dpkg-buildpackage -us -uc -sa -j4)
