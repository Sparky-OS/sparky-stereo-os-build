#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# Run in a prepared Debian builder with the edition runtime archive configured.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
: "${OUT:?}" "${SOURCE_DATE_EPOCH:?the recipe date from build-provenance.sh}"
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS=parallel=4
mkdir -p "$OUT"
: "${LAYER:?the pinned stereo-layer siblings, installed before the build dependencies}"
(cd "$LAYER" && sha256sum --check --quiet "$HERE/layer-1.23.2.sha256")
inherited_siblings=${SPARKY_LC_SIBLINGS_FILE:-}
export SPARKY_LC_SIBLINGS_FILE="$OUT/layer-siblings.txt"
: >"$SPARKY_LC_SIBLINGS_FILE"
while read -r sum filename; do
    realpath "$LAYER/$filename" >>"$SPARKY_LC_SIBLINGS_FILE"
done <"$HERE/layer-1.23.2.sha256"
: "${DECLARE:?the pinned stereo-declare siblings, installed before build dependencies}"
(cd "$DECLARE" && sha256sum --check --quiet "$HERE/declare-1.12.2.sha256")
while read -r sum filename; do
    realpath "$DECLARE/$filename" >>"$SPARKY_LC_SIBLINGS_FILE"
done <"$HERE/declare-1.12.2.sha256"
# The round and prior successors remain part of the gate's supplied universe.
python3 - "$inherited_siblings" "$SPARKY_LC_SIBLINGS_FILE" <<'SIBLINGS'
from pathlib import Path
import hashlib, sys
paths = []
if sys.argv[1]:
    paths.extend(Path(sys.argv[1]).read_text().splitlines())
output = Path(sys.argv[2])
paths.extend(output.read_text().splitlines())
selected = {}
for value in paths:
    p = Path(value)
    if p.name in selected:
        other = selected[p.name]
        if other != p:
            assert hashlib.sha256(other.read_bytes()).digest() == hashlib.sha256(p.read_bytes()).digest(), p.name
    else:
        selected[p.name] = p
output.write_text(''.join(str(p) + '\n' for p in selected.values()))
SIBLINGS
for package in libstereo-declare1 libstereo-declare-dev; do
    test "$(dpkg-query -W -f='${Version}' "$package")" = 1.12.2-1+lc1
done
for package in libstereo-layer1 libstereo-policy1 libstereo-layer-dev libstereo-policy-dev; do
    test "$(dpkg-query -W -f='${Version}' "$package")" = 1.23.2-1+lc1
done
cd "$OUT"
HTTPS_ONLY_APT_CONF="$OUT/https-only-apt.conf" sh /run/https-only-apt.sh
export APT_CONFIG="$OUT/https-only-apt.conf"
if [ -n "${SOURCE_INPUT:-}" ]; then
    cp "$SOURCE_INPUT"/*.dsc "$SOURCE_INPUT"/*.tar.* "$OUT/"
else
    apt-get source --download-only kamoso=26.04.0-1
fi
sha256sum -c "$HERE/source.sha256"
dpkg-source -x kamoso_26.04.0-1.dsc source
mkdir -p source/debian/patches
install -m644 "$HERE/patches/0001-follow-the-session-default-camera.patch" source/debian/patches/
install -m644 "$HERE/patches/0002-stereo-camera-viewfinder.patch" source/debian/patches/
install -m644 "$HERE/patches/0003-effects-grid-removed-row-builds-no-pipeline.patch" source/debian/patches/
install -m644 "$HERE/patches/0004-effect-previews-convert-before-the-sink.patch" source/debian/patches/
printf '%s\n' 0001-follow-the-session-default-camera.patch 0002-stereo-camera-viewfinder.patch \
    0003-effects-grid-removed-row-builds-no-pipeline.patch 0004-effect-previews-convert-before-the-sink.patch \
    >>source/debian/patches/series
python3 - source/debian/control <<'CONTROL'
from pathlib import Path
import sys
p = Path(sys.argv[1])
# Keep build and runtime dependencies aligned with capture and gallery features.
s = p.read_text().replace('Build-Depends:', 'Build-Depends: gstreamer1.0-pipewire (>= 1.6.9-2+stereo3d1), gstreamer1.0-plugins-good (>= 1.28.9-dmo1+stereo3d1), gstreamer1.0-qt6 (>= 1.28.9-dmo1+stereo3d1), frei0r-plugins (>= 1:3.7.1-dmo1+stereo3d1), gstreamer1.0-plugins-ugly, gstreamer1.0-libav, kimageformat6-plugins, libstereo-layer-dev (>= 1.23.2), libstereo-policy-dev (>= 1.23.2), qt6-multimedia-dev, qml6-module-org-kde-kirigami <!nocheck>, qml6-module-qtqml <!nocheck>, qml6-module-qtquick <!nocheck>, qml6-module-qtquick-controls <!nocheck>, qml6-module-qtquick-dialogs <!nocheck>, qml6-module-qtquick-layouts <!nocheck>, gstreamer1.0-plugins-bad <!nocheck>,').replace('\nDepends:', '\nDepends: gstreamer1.0-pipewire (>= 1.6.9-2+stereo3d1), gstreamer1.0-plugins-good (>= 1.28.9-dmo1+stereo3d1), gstreamer1.0-qt6 (>= 1.28.9-dmo1+stereo3d1), frei0r-plugins (>= 1:3.7.1-dmo1+stereo3d1), gstreamer1.0-plugins-ugly, gstreamer1.0-libav, kimageformat6-plugins, libstereo-declare1 (>= 1.12.2), gstreamer1.0-gl, libstereo-layer1 (>= 1.23.2), libstereo-policy1 (>= 1.23.2),', 1)
p.write_text(s)
CONTROL
python3 - source/debian/rules <<'RULES'
from pathlib import Path
import sys
p = Path(sys.argv[1])
# Debian ignores test failures (a leading '-'); the edition's tests must stop the build when they fail.
s = p.read_text()
old = '\t-xvfb-run -a --server-args="-screen 0 1024x768x24 +extension GLX" -- \\\n'
assert s.count(old) == 1
p.write_text(s.replace(old, old.replace('\t-xvfb-run', '\txvfb-run')))
RULES
TOOLKIT="$TOOLKIT" python3 - "$OUT/source/debian/changelog" <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ['TOOLKIT'] + '/repo')
import reproducible
p = pathlib.Path(sys.argv[1])
# the house's one date form (always UTC, +0000); the build of 2026-11-15 wrote the same instant as -0000
date = reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('kamoso (26.04.0-1+stereo3d2) unstable; urgency=medium\n\n'
             '  * Add the shared camera packing and declared stereo viewfinder.\n'
             '  * Build no effect preview for a removed effect row.\n'
             '  * Convert an effect preview\'s format before its sink.\n\n'
             ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n' + p.read_text())
PY
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . 26.04.0-1+stereo3d2+lc1
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
dpkg-buildpackage -us -uc -sa -j4
cd "$OUT"
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*26.04.0-1+stereo3d2+lc1*.deb
