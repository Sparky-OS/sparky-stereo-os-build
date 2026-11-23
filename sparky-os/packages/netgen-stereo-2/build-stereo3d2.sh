#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23. Copyright 2026 under the GNU GPL3 License.
# Sparky Stereo OS, row 50 step 5: the binary packages of netgen 6.2.2606+dfsg1-3+stereo3d2+lc1 from the source
# prepare-source-stereo3d2.sh made, through Lean Code, then lean.release check-debs (which writes the build record).
# Usage, inside a build container whose apt sources hold the build dependencies (as uid 1000 with them installed):
#   build-stereo3d2.sh SOURCE_DIR WORK TOOLKIT
# Environment: SPARKY_LC_ARCHIVE_CONFIG, SPARKY_LC_SCRATCH, SPARKY_LC_SIBLINGS_FILE (libstereo-declare1 1.12.2),
# SPARKY_LC_PREVIOUS_DIR (the +stereo3d1+lc1 binaries), and the provenance variables of build-provenance.sh.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
src=$(realpath "$1"); work=$(realpath -m "$2"); toolkit=$(realpath "$3")
V=6.2.2606+dfsg1-3+stereo3d2+lc1
: "${SPARKY_LC_ARCHIVE_CONFIG:?}" "${SPARKY_LC_SCRATCH:?}"
mkdir -p "$work"; [ -z "$(ls -A "$work")" ] || { echo "$work is not empty" >&2; exit 1; }
cd "$work"
cp "$src/netgen_$V.dsc" "$src/netgen_$V.debian.tar.xz" "$src/netgen_6.2.2606+dfsg1.orig.tar.xz" .
dpkg-source -x "netgen_$V.dsc" source > /dev/null
cd source
[ "$(dpkg-parsechangelog -S Version)" = "$V" ]
dpkg-checkbuilddeps
dpkg-buildpackage -b -us -uc -j4
cd "$work"
PYTHONPATH="$toolkit" python3 -m lean.release check-debs "$work/"*.deb
