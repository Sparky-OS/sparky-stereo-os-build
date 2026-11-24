#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
: "${OUT:?}" "${SOURCE_DATE_EPOCH:?the recipe date from build-provenance.sh}"
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS=parallel=4
mkdir -p "$OUT"
cd "$OUT"
HTTPS_ONLY_APT_CONF="$OUT/https-only-apt.conf" sh /run/https-only-apt.sh
export APT_CONFIG="$OUT/https-only-apt.conf"
if [ -n "${SOURCE_INPUT:-}" ]; then
    cp "$SOURCE_INPUT"/*.dsc "$SOURCE_INPUT"/*.tar.* "$OUT/"
else
    apt-get source --download-only frei0r-dmo=1:3.7.1-dmo1
fi
sha256sum -c "$HERE/source.sha256"
dpkg-source -x frei0r-dmo_3.7.1-dmo1.dsc source
mkdir -p source/debian/patches
for patch in 0001-immutable-parameter-metadata.patch; do
    install -m644 "$HERE/patches/$patch" source/debian/patches/
    printf '%s\n' "$patch" >>source/debian/patches/series
done
TOOLKIT="$TOOLKIT" python3 - source/debian/changelog <<'PY'
import os,pathlib,sys
sys.path.insert(0,os.environ['TOOLKIT']+'/repo')
import reproducible
p=pathlib.Path(sys.argv[1]);date=reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('frei0r-dmo (1:3.7.1-dmo1+stereo3d1) unstable; urgency=medium\n\n  * Keep plugin parameter metadata immutable during instance construction.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+date+'\n\n'+p.read_text())
PY
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . 1:3.7.1-dmo1+stereo3d1+lc1
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
dpkg-buildpackage -us -uc -sa -j4
cd "$OUT"
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*3.7.1-dmo1+stereo3d1+lc1*.deb
