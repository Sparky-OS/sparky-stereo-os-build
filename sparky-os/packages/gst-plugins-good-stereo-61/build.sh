#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
: "${OUT:?}" "${SOURCE_DATE_EPOCH:?the recipe date from build-provenance.sh}"
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Campos Ramos'
export DEB_BUILD_OPTIONS=parallel=4
mkdir -p "$OUT"
cd "$OUT"
HTTPS_ONLY_APT_CONF="$OUT/https-only-apt.conf" sh /run/https-only-apt.sh
export APT_CONFIG="$OUT/https-only-apt.conf"
apt-get source --download-only gst-plugins-good1.0-dmo=1.28.9-dmo1
dpkg-source -x gst-plugins-good1.0-dmo_1.28.9-dmo1.dsc source
mkdir -p source/debian/patches
install -m644 "$HERE/patches/0001-qtmux-st3d-from-multiview-caps.patch" source/debian/patches/
printf '%s\n' 0001-qtmux-st3d-from-multiview-caps.patch >>source/debian/patches/series
TOOLKIT="$TOOLKIT" python3 - source/debian/changelog <<'PY'
import os,pathlib,sys
sys.path.insert(0,os.environ['TOOLKIT']+'/repo')
import reproducible
p=pathlib.Path(sys.argv[1]);date=reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('gst-plugins-good1.0-dmo (1.28.9-dmo1+stereo3d1) unstable; urgency=medium\n\n  * Write st3d video sample entries from multiview caps in qtmux.\n\n -- Daniel Campos Ramos <Capitain_Jack@yahoo.com>  '+date+'\n\n'+p.read_text())
PY
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . 1.28.9-dmo1+stereo3d1+lc1
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
dpkg-buildpackage -us -uc -sa -j4
cd "$OUT"
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*1.28.9-dmo1+stereo3d1+lc1*.deb
