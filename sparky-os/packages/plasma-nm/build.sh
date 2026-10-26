#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/26
# Copyright 2026 under the GNU GPL3 License
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names the unmodified Debian 6.7.4-2 source and its adjacent archives.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set an explicit public signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?Set private archive qualification scratch}"
: "${LEAN_TOOLKIT:?Set the accepted archive-backed Lean Code toolkit}"
[ -f "$LEAN_TOOLKIT/lean/archive.py" ] || { echo 'Archive-backed Lean Code toolkit required' >&2; exit 1; }
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian plasma-nm_6.7.4-2.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS='nocheck parallel=4' DEB_BUILD_PROFILES=nocheck
export LC_ALL=C.UTF-8
VERSION=4:6.7.4-2+stereo3d1
printf '%s  %s\n' d746495924ec0cd0369fd5015e0a7254b2fab0e81dfe456bdc36b3592414bf91 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/source" ]
mkdir -p "$BUILD_ROOT" "$OUT/source" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/plasma-nm_6.7.4.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
mkdir -p debian/patches
cp "$HERE/connectivity-check.patch" debian/patches/
cp "$TOOLKIT/translations/plasma-nm-connectivity-check.po.patch" debian/patches/
printf '%s\n' connectivity-check.patch plasma-nm-connectivity-check.po.patch >> debian/patches/series
dpkg-source --before-build .
python3 - <<'PY'
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
text = text.replace('libkf6networkmanagerqt-dev (>= 6.26.0~)', 'libkf6networkmanagerqt-dev (>= 6.30.0-1+stereo3d1)')
text = text.replace('${shlibs:Depends}', '${shlibs:Depends}, libkf6networkmanagerqt6 (>= 6.30.0-1+stereo3d1)')
text = text.replace('Homepage: https://invent.kde.org/plasma/plasma-nm',
                    'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', 1)
path.write_text(text)
PY
dch --newversion "$VERSION" --distribution mashtabba \
	'Provide an asynchronous, error-reporting NetworkManager connectivity-check choice.'
dpkg-source -b .
cp "$BUILD_ROOT"/*.dsc "$BUILD_ROOT"/*.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/plasma-nm_${VERSION#*:}.dsc" "$BUILD_ROOT/lean-source"
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare "$BUILD_ROOT/lean-source" "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
cd "$BUILD_ROOT/lean-source"
dpkg-buildpackage -us -uc -j4
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs "$BUILD_ROOT"/*+lc1_*.deb
cp "$BUILD_ROOT"/*+lc1_*.deb "$OUT/"
cp "$BUILD_ROOT"/*+lc1.dsc "$BUILD_ROOT"/*+lc1.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/source/"
cp .sparky-lc/source.json "$OUT/native-source.json"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
