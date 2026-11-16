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
cd "$OUT"
apt-get source --download-only kamoso=26.04.0-1
dpkg-source -x kamoso_26.04.0-1.dsc source
mkdir -p source/debian/patches
install -m644 "$HERE/patches/0001-follow-the-session-default-camera.patch" source/debian/patches/
printf '%s\n' 0001-follow-the-session-default-camera.patch >>source/debian/patches/series
TOOLKIT="$TOOLKIT" python3 - "$OUT/source/debian/changelog" <<'PY'
import os, pathlib, sys
sys.path.insert(0, os.environ['TOOLKIT'] + '/repo')
import reproducible
p = pathlib.Path(sys.argv[1])
# the house's one date form (always UTC, +0000); the build of 2026-11-15 wrote the same instant as -0000
date = reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('kamoso (26.04.0-1+stereo3d1) unstable; urgency=medium\n\n'
             '  * Follow the session default camera unless a camera was chosen in Kamoso.\n\n'
             ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + date + '\n\n' + p.read_text())
PY
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . 26.04.0-1+stereo3d1+lc1
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
dpkg-buildpackage -us -uc -sa -j4
cd "$OUT"
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*26.04.0-1+stereo3d1+lc1*.deb
