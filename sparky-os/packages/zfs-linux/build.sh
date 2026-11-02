#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Run in a fresh Debian testing build container, with Debian's source and build dependencies.
# SOURCE_DSC and its adjacent archives are the unmodified Debian 2.4.4-1 source.
# Last update 2026/11/02
set -euo pipefail
export TEST_JOBS=4
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set the signed public archive configuration}"
: "${SPARKY_LC_SCRATCH:?Set archive qualification scratch}"
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian zfs-linux_2.4.4-1.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable SSD directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4 LC_ALL=C.UTF-8
VERSION=2.4.4-1+stereo3d1
printf '%s  %s\n' eee05c1c5a638cfec621633a305e156f85c790f7ed358f62f033450c180c62e0 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/source" ]
mkdir -p "$BUILD_ROOT" "$OUT/source" "$OUT/authored"
python3 "$HERE/../../../tools/copy-recipe.py" "$HERE" "$BUILD_ROOT/recipe"
HERE=$BUILD_ROOT/recipe
cp "$(dirname "$SOURCE_DSC")"/zfs-linux_2.4.4.orig.tar.gz "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
cp "$HERE"/patches/*.patch debian/patches/
cat "$HERE/patches/series" >> debian/patches/series
dpkg-source --before-build .
python3 - <<'PY'
from pathlib import Path
p = Path('debian/control')
s = p.read_text()
original = next(line for line in s.splitlines() if line.startswith('Maintainer: '))
s = s.replace(original, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + original, 1)
s = s.replace('Homepage: https://zfsonlinux.org/', 'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', 1)
p.write_text(s)
PY
dch --newversion "$VERSION" --distribution mashtabba \
	'Backport OpenZFS Linux 7.3 compatibility by Rob Norris, co-developed with TheAlmightyOgreLord, and the supported-kernel declaration by ooonea.eth.'
dpkg-source -b .
cp "$BUILD_ROOT"/*.dsc "$BUILD_ROOT"/*.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/zfs-linux_$VERSION.dsc" "$BUILD_ROOT/lean-source"
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare "$BUILD_ROOT/lean-source" "$VERSION+lc1" --toolkit "$TOOLKIT" --build-dependency clang
cd "$BUILD_ROOT/lean-source"
dpkg-buildpackage -us -uc -j4
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs "$BUILD_ROOT"/*+lc1_*.deb
PYTHONPATH="$TOOLKIT" python3 -m lean.release check-identity "$BUILD_ROOT"/*+lc1_*.deb
cp "$BUILD_ROOT"/*+lc1_*.deb "$OUT/"
cp "$BUILD_ROOT"/*+lc1.dsc "$BUILD_ROOT"/*+lc1.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/source/"
cp .sparky-lc/source.json "$OUT/native-source.json"
touch "$OUT/.keep"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
sync
