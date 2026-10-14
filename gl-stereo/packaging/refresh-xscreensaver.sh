#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
cd /build/sources
tree=xscreensaver-6.09+dfsg1
mkdir -p /build/xscreensaver-metadata
cp "$tree"/debian/{control,copyright,changelog} /build/xscreensaver-metadata/
cp "$tree/debian/patches/stereo-show.patch" /build/xscreensaver-metadata/
# Only the failed, reproducible source/build tree is discarded.
python3 - <<'PY'
import shutil
shutil.rmtree('/build/sources/xscreensaver-6.09+dfsg1')
PY
dpkg-source --no-check -x xscreensaver_6.09+dfsg1-2.dsc
cp /build/xscreensaver-metadata/{control,copyright,changelog} "$tree/debian/"
cp /build/xscreensaver-metadata/stereo-show.patch "$tree/debian/patches/"
printf '\nstereo-show.patch\n' >> "$tree/debian/patches/series"
