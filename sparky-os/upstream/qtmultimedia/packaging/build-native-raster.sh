#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run in the isolated build image against the published +10 source archive.
set -euo pipefail
export DEBEMAIL=Capitain_Jack@yahoo.com
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS='nocheck parallel=4'
input=${1:?published Qt Multimedia source directory}
work=${2:?new build directory}
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$work"
cp "$input/qt6-multimedia_6.11.2.orig.tar.xz" "$work/"
dpkg-source -x "$input/qt6-multimedia_6.11.2-3+stereo3d10+lc1.dsc" "$work/source"
cd "$work/source"
cp "$recipe/0014-native-raster-sink.patch" debian/patches/
printf '%s\n' 0014-native-raster-sink.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push
python3 - <<'PY'
from pathlib import Path
p=Path('debian/libqt6multimedia6.symbols')
s=p.read_text()
for symbol in ('_ZN10QVideoSink21setPreserveNativeSizeEb',
               '_ZN10QVideoSink25preserveNativeSizeChangedEb',
               '_ZNK10QVideoSink18preserveNativeSizeEv'):
    s += f' {symbol}@Qt_6 6.11.2-3+stereo3d11\n'
p.write_text(s)
PY
dch --newversion 6.11.2-3+stereo3d11+lc1 --distribution UNRELEASED \
 'Add a default-off QVideoSink native-raster capability for consumers that preserve source samples and pixel aspect; retain declared marks and existing consumer behavior.'
# The published source already carries the qualified native/payload Lean Code pipeline.
dpkg-buildpackage -S -us -uc -d
cd "$work"
dpkg-source -x qt6-multimedia_6.11.2-3+stereo3d11+lc1.dsc binary-source
cd binary-source
dpkg-buildpackage -B -us -uc
