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
for package in libstereo-declare1 libstereo-declare-dev; do
    test "$(dpkg-query -W -f='${Version}' "$package")" = 1.12.2-1+lc1
done
for package in libstereo-layer1 libstereo-policy1 libstereo-layer-dev libstereo-policy-dev; do
    test "$(dpkg-query -W -f='${Version}' "$package")" = 1.23.2-1+lc1
done
cd "$OUT"
HTTPS_ONLY_APT_CONF="$OUT/https-only-apt.conf" sh /run/https-only-apt.sh
export APT_CONFIG="$OUT/https-only-apt.conf"
apt-get source --download-only kamoso=26.04.0-1
dpkg-source -x kamoso_26.04.0-1.dsc source
mkdir -p source/debian/patches
install -m644 "$HERE/patches/0001-follow-the-session-default-camera.patch" source/debian/patches/
install -m644 "$HERE/patches/0002-stereo-camera-viewfinder.patch" source/debian/patches/
printf '%s\n' 0001-follow-the-session-default-camera.patch 0002-stereo-camera-viewfinder.patch >>source/debian/patches/series
python3 - source/debian/control <<'CONTROL'
from pathlib import Path
import sys
p = Path(sys.argv[1])
# Only the binary Depends field; never rewrite Build-Depends.
s = p.read_text().replace('Build-Depends:', 'Build-Depends: gstreamer1.0-plugins-good (>= 1.28.9-dmo1+stereo3d1), gstreamer1.0-plugins-ugly, gstreamer1.0-libav, kimageformat6-plugins, libstereo-layer-dev (>= 1.23.2), libstereo-policy-dev (>= 1.23.2), qt6-multimedia-dev,').replace('\nDepends:', '\nDepends: gstreamer1.0-plugins-good (>= 1.28.9-dmo1+stereo3d1), gstreamer1.0-plugins-ugly, gstreamer1.0-libav, kimageformat6-plugins, libstereo-declare1 (>= 1.12.2), gstreamer1.0-gl, libstereo-layer1 (>= 1.23.2), libstereo-policy1 (>= 1.23.2),', 1)
p.write_text(s)
CONTROL
TOOLKIT="$TOOLKIT" python3 - "$OUT/source/debian/changelog" <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ['TOOLKIT'] + '/repo')
import reproducible
p = pathlib.Path(sys.argv[1])
# the house's one date form (always UTC, +0000); the build of 2026-11-15 wrote the same instant as -0000
date = reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('kamoso (26.04.0-1+stereo3d2) unstable; urgency=medium\n\n'
             '  * Add the shared camera packing and declared stereo viewfinder.\n\n'
             ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n' + p.read_text())
PY
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . 26.04.0-1+stereo3d2+lc1
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
dpkg-buildpackage -us -uc -sa -j4
cd "$OUT"
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*26.04.0-1+stereo3d2+lc1*.deb
