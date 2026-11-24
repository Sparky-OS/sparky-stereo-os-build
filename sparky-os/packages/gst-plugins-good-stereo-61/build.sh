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
    apt-get source --download-only gst-plugins-good1.0-dmo=1.28.9-dmo1
fi
sha256sum -c "$HERE/source.sha256"
dpkg-source -x gst-plugins-good1.0-dmo_1.28.9-dmo1.dsc source
mkdir -p source/debian/patches
for patch in 0001-qtmux-st3d-from-multiview-caps.patch 0002-qml-gl-refresh-material-caps.patch 0003-flvmux-late-caps-test.patch; do
    install -m644 "$HERE/patches/$patch" source/debian/patches/
    printf '%s\n' "$patch" >>source/debian/patches/series
done
TOOLKIT="$TOOLKIT" python3 - source/debian/changelog <<'PY'
import os,pathlib,sys
sys.path.insert(0,os.environ['TOOLKIT']+'/repo')
import reproducible
p=pathlib.Path(sys.argv[1]);date=reproducible.rfc2822(os.environ['SOURCE_DATE_EPOCH'])
p.write_text('gst-plugins-good1.0-dmo (1.28.9-dmo1+stereo3d1) unstable; urgency=medium\n\n  * Write st3d video sample entries from multiview caps in qtmux.\n  * Carry the upstream Qt material caps initialization fix by Will.\n  * Carry the late-caps synchronization repair by Dominique Leroux.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '+date+'\n\n'+p.read_text())
PY
cd source
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . 1.28.9-dmo1+stereo3d1+lc1
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
dpkg-buildpackage -us -uc -sa -j4
# DMO's rules ignore dh_auto_test errors; qualification must retain its result.
python3 - <<'TESTS'
from pathlib import Path
import collections, json
rows = [json.loads(line) for line in Path('obj-x86_64-linux-gnu/meson-logs/testlog.json').read_text().splitlines()]
assert rows, 'No upstream test results'
print('Upstream test results:', dict(collections.Counter(row['result'] for row in rows)))
assert all(not row['is_fail'] for row in rows), [(row['name'], row['result']) for row in rows if row['is_fail']]
TESTS
cd "$OUT"
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*1.28.9-dmo1+stereo3d1+lc1*.deb
