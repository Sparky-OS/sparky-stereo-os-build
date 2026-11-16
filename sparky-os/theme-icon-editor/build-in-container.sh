#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
set -eu
ulimit -c 0
export HTTPS_ONLY_APT_CONF=/build/https-only-apt.conf
sh /run/https-only-apt.sh
export APT_CONFIG="$HTTPS_ONLY_APT_CONF"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEBEMAIL='Capitain_Jack@yahoo.com'
export DEB_BUILD_OPTIONS=parallel=2
export HOME=/build/home
export TMPDIR=/build/tmp
mkdir -p "$HOME" "$TMPDIR" /build/output
python3 /source/tools/copy-recipe.py /source/sparky-os/theme-icon-editor /build/output/sparky-stereo-theme-editor-0.1.0
cd /build/output/sparky-stereo-theme-editor-0.1.0
PYTHONPATH=/source/sparky-os python3 -m lean.debian_prepare . 0.1.0+lc1 --toolkit /source/sparky-os \
 --preserve-source geometry/kwin/src/scene/stereodepth.cpp 'The depth adapter extracts these exact source bytes and records their hash' \
 --preserve-source geometry/kwin/src/effect/globals.h 'The depth adapter extracts the exact enum and records this source hash'
python3 /source/sparky-os/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc
cd /build/output
PYTHONPATH=/source/sparky-os python3 -m lean.release check-debs ./*.deb
PYTHONPATH=/source/sparky-os python3 -m lean.release check-identity ./*.deb
lintian --fail-on error --display-info ./*.changes
python3 - <<'PY'
from pathlib import Path
import json
records=list(Path('.').glob('*.sparky-build.json'))
assert records, 'No build record'
for p in records:
    r=json.loads(p.read_text())
    assert r['unrecorded']==[], r['unrecorded']
    assert r.get('recipeDirty') is False, 'Commit the recipe before a release build'
print('PASS: complete build record, nothing unrecorded, committed recipe')
PY
