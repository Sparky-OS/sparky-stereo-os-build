#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/15
# A conventional debhelper source, made the edition's way: the committed recipe is copied, lean.debian_prepare adds the Lean Code
# stages and the +lc1 entry, dpkg-buildpackage builds the source package, the runtime archive and its HR companion.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
PACKAGE=sparky-stereo-camera
VERSION=0.1.0
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(date -u -d "2026-11-15 09:00:00" +%s)}
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Ramos (Capitain Jack)"
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.camera.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SRC=$WORK/$PACKAGE-$VERSION
python3 "$TOOLKIT/../tools/copy-recipe.py" "$HERE" "$SRC"
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$SRC"
(cd "$SRC" && PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . "$VERSION+lc1" --build-dependency sparky-stereo-problems)
(cd "$SRC" && PYTHONPATH="$TOOLKIT" dpkg-buildpackage -us -uc -sa -j"${JOBS:-4}" >"$WORK/build.log" 2>&1) || { tail -40 "$WORK/build.log"; exit 1; }
cp "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/*.json "$OUT/" 2>/dev/null || true
cp "$WORK/build.log" "$OUT/build.log"
