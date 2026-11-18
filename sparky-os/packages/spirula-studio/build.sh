#!/bin/bash
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
: "${SPIRULA_SOURCE:?Set SPIRULA_SOURCE to the committed edition source checkout}"
: "${OUT:?Set OUT to the source and binary output directory}"
: "${SPARKY_BUILD_INVOCATION:?Run build-container.sh or initialize build-provenance.sh on the host}"
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set the signed archive-backed link gate configuration}"
: "${SPARKY_LC_SCRATCH:?Set an owned disposable link-gate workspace}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$HERE" log -1 --format=%ct -- .)}
export DEB_BUILD_OPTIONS="parallel=${JOBS:-4}"
python3 "$HERE/compose-source.py" --source "$SPIRULA_SOURCE" --out "$OUT" --toolkit "$TOOLKIT"
ROOT=$OUT/spirula-studio-2026.11.12
# Seal authored source before the native Lean Code build projection.
(cd "$OUT" && dpkg-source -b "$(basename "$ROOT")")
(cd "$ROOT" && dpkg-buildpackage -us -uc -b -j"${JOBS:-4}")
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs "$OUT"/*.deb
sync
