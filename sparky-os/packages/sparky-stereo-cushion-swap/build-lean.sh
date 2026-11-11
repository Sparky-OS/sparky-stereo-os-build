#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Build the authored recipe through the same native adapter as the round cohort.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to an empty build directory}
: "${SPARKY_LC_ARCHIVE_CONFIG:?signed archive configuration for the link gate}"
: "${SPARKY_LC_SCRATCH:?private link-gate scratch directory}"
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
export PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
export DEB_BUILD_OPTIONS=parallel=4
OUT="$OUT/authored" bash "$HERE/build.sh"
dpkg-source -x "$OUT/authored/sparky-stereo-cushion-swap_0.3.4.dsc" "$OUT/source"
# The authored source above is dated by its own changelog (build.sh); the +lc1 entry is dated by this recipe, never by the clock
# (ORDER 421b): SOURCE_DATE_EPOCH, else the last commit touching this folder.
REPRO="$HERE/../../repo/reproducible.py"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" epoch "$HERE")}
python3 -m lean.debian_custom "$OUT/source" 0.3.4+lc1 --toolkit "$HERE/../.."
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" "$OUT/source"
(cd "$OUT/source" && dpkg-buildpackage -us -uc -j4)
# Every resulting runtime/HR archive enters the ordinary cohort link gate.
args=()
[ -z "${SPARKY_LC_SIBLINGS_FILE:-}" ] || args+=(--siblings-file "$SPARKY_LC_SIBLINGS_FILE")
[ -z "${SPARKY_LC_PREVIOUS_SIBLINGS_FILE:-}" ] || args+=(--previous-siblings-file "$SPARKY_LC_PREVIOUS_SIBLINGS_FILE")
python3 -m lean.release check-link "${args[@]}" --min-free-gib "${SPARKY_LC_MIN_FREE_GIB:-2}" \
    --root-min-free-gib "${SPARKY_LC_ROOT_MIN_FREE_GIB:-12}" "$OUT"/*.deb
