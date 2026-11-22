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
VERSION=0.1.2
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:?the host passes the date of the recipe: build-provenance.sh}
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Ramos (Capitain Jack)"
mkdir -p "$OUT"
: "${LAYER:?the pinned stereo-layer siblings, installed before the build dependencies}"
(cd "$LAYER" && sha256sum --check --quiet "$HERE/layer-1.23.2.sha256")
export SPARKY_LC_SIBLINGS_FILE="$OUT/layer-siblings.txt"
: >"$SPARKY_LC_SIBLINGS_FILE"
while read -r sum filename; do
    realpath "$LAYER/$filename" >>"$SPARKY_LC_SIBLINGS_FILE"
done <"$HERE/layer-1.23.2.sha256"
for package in libstereo-layer1 libstereo-policy1 libstereo-layer-dev libstereo-policy-dev; do
    test "$(dpkg-query -W -f='${Version}' "$package")" = 1.23.2-1+lc1
done
WORK=$(mktemp -d "$OUT/.camera.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SRC=$WORK/source   # not named package-version: dch renames a folder that is
python3 "$TOOLKIT/../tools/copy-recipe.py" "$HERE" "$SRC"
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$SRC"
(cd "$SRC" && PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . "$VERSION+lc1" --build-dependency sparky-stereo-problems)
(cd "$SRC" && PYTHONPATH="$TOOLKIT" dpkg-buildpackage -us -uc -sa -j"${JOBS:-4}" >"$WORK/build.log" 2>&1) || { tail -40 "$WORK/build.log"; exit 1; }
cp "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/*.json "$OUT/" 2>/dev/null || true
cp "$WORK/build.log" "$OUT/build.log"
# the release gate: every archive and its HR companions carry a valid lc1 record, and the build record is written beside them
(cd "$OUT" && PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*.deb)
