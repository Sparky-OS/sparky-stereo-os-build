#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/25
# A conventional debhelper source, made the edition's way: the committed recipe is copied, lean.debian_prepare adds the Lean Code
# stages and the +lc1 entry, dpkg-buildpackage builds the source package, the runtime archive and its HR companion.
# SIBLINGS: the folder of gl-stereo's packages at 0.4.6, which the page depends on and the published round does not hold yet.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.1
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:?the host passes the date of the recipe: build-provenance.sh}
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Ramos (Capitain Jack)"
mkdir -p "$OUT"
test "$(dpkg-query -W -f='${Version}' libstereo-declare-dev)" = 1.12.2-1+lc1
: "${SIBLINGS:?the folder of the gl-stereo 0.4.6 packages the page depends on}"
export SPARKY_LC_SIBLINGS_FILE="$OUT/siblings.txt"
ls "$SIBLINGS"/gl-stereo*_0.4.6-1+lc1_amd64.deb "$SIBLINGS"/libstereoshow1_0.4.6-1+lc1_amd64.deb | grep -v -e dbgsym -e lc-hr > "$SPARKY_LC_SIBLINGS_FILE"
WORK=$(mktemp -d "$OUT/.screensavers.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SRC=$WORK/source   # not named package-version: dch renames a folder that is
python3 "$TOOLKIT/../tools/copy-recipe.py" "$HERE" "$SRC"
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" "$SRC"
(cd "$SRC" && PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . "$VERSION+lc1")
(cd "$SRC" && PYTHONPATH="$TOOLKIT" dpkg-buildpackage -us -uc -sa -j"${JOBS:-4}" >"$WORK/build.log" 2>&1) || { cp "$WORK/build.log" "$OUT/build.log"; tail -40 "$WORK/build.log"; exit 1; }
cp "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$WORK"/*.json "$OUT/" 2>/dev/null || true
cp "$WORK/build.log" "$OUT/build.log"
# the release gate: every archive and its HR companions carry a valid lc1 record, and the build record is written beside them
(cd "$OUT" && PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*.deb)
