#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the Oxygen widget style for Qt 5 programs, part of the whole Oxygen suite (queue row 59; Daniel,
# 2026-10-14: "we need the entire oxygen suite from kde", said after a Debian update dropped Oxygen pieces on his laptop).
# KDE still builds it: plasma/oxygen keeps option(BUILD_QT5 "Build Qt5 style" ON) at v6.7.4 and on master. Debian's
# oxygen 4:6.6.3-1 dropped it ("Drop Qt5/KF5 support", Aurélien Couderc) and the binaries left unstable on 2026-04-08 as
# "[auto-cruft] NBS (no longer built by oxygen, no reverse dependencies)"; trixie still has them (4:6.3.4-1).
# This source, oxygen-qt5, is KDE's oxygen 6.7.4 release (Debian's orig tarball, KDE's signature beside it) with Debian's
# 4:6.7.4-1 packaging reduced to the three Qt 5 packages of Debian's 4:6.5.4-1 (their stanzas and .install files), built
# with BUILD_QT5=ON and BUILD_QT6=OFF. Upstream installs the colour schemes, cursors, decoration, look and feel,
# wallpapers and translations only in its Qt 6 block, so nothing here touches Debian's Qt 6 packages; the Qt 5 settings
# library takes its catalogue from Debian's liboxygenstyleconfig-data. Its own source name keeps Debian's oxygen ours to
# leave alone. Lean Code at +lc1.
# Run inside a clean distribution build container with the packages of ./build-depends installed.
# SOURCE_DSC names Debian's unmodified oxygen_6.7.4-1.dsc and its adjacent archives.
# Last update 2026/11/23
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set an explicit public signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?Set private archive qualification scratch}"
: "${LEAN_TOOLKIT:?Set the accepted archive-backed Lean Code toolkit}"
[ -f "$LEAN_TOOLKIT/lean/archive.py" ] || { echo 'Archive-backed Lean Code toolkit required' >&2; exit 1; }
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian oxygen_6.7.4-1.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS="parallel=${JOBS:-4}"
export LC_ALL=C.UTF-8
VERSION=4:6.7.4-1+sparky1
V=${VERSION#*:}
SRC=$(dirname "$SOURCE_DSC")
printf '%s  %s\n' b9fa5fcb405fb000cd0b0198f8613b3df3b4d672331f6a0d1dd848820f5a0003 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/authored" ]
mkdir -p "$BUILD_ROOT" "$OUT/authored"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/debian-oxygen"
# the same upstream tarball under this source's name, KDE's signature beside it
cp "$SRC/oxygen_6.7.4.orig.tar.xz" "$BUILD_ROOT/oxygen-qt5_6.7.4.orig.tar.xz"
cp "$SRC/oxygen_6.7.4.orig.tar.xz.asc" "$BUILD_ROOT/oxygen-qt5_6.7.4.orig.tar.xz.asc"
mkdir "$BUILD_ROOT/authored"
tar -C "$BUILD_ROOT/authored" --strip-components=1 -xf "$BUILD_ROOT/oxygen-qt5_6.7.4.orig.tar.xz"
cp -a "$BUILD_ROOT/debian-oxygen/debian" "$BUILD_ROOT/authored/debian"
cd "$BUILD_ROOT/authored"
rm -f debian/kde-style-oxygen-qt6.* debian/kwin-decoration-oxygen.* debian/liboxygenstyle6-6.* debian/liboxygenstyleconfig6-6.* \
	debian/liboxygenstyleconfig-data.* debian/oxygen-wallpapers.* debian/plasma-theme-oxygen.*
cp "$HERE"/debian-qt5/*.install "$HERE"/debian-qt5/*.lintian-overrides "$HERE"/debian-qt5/not-installed debian/
python3 - "$HERE" <<'PY'
import re, sys
from pathlib import Path
here = Path(sys.argv[1])
control = Path('debian/control')
source = control.read_text().split('\n\n')[0]
lines = source.splitlines()
out = []
skip = False
for line in lines:
    if skip and line[:1] in (' ', '\t'):
        continue
    skip = False
    if line.startswith('Source: '):
        out.append('Source: oxygen-qt5')
    elif line.startswith('Maintainer: '):
        out += ['Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>', 'XSBC-Original-' + line]
    elif line.startswith('Build-Depends: '):
        deps = [d.strip() for d in (here / 'build-depends').read_text().splitlines() if d.strip()]
        out.append('Build-Depends: ' + ',\n               '.join(deps) + ',')
        skip = True
    elif line.startswith('Homepage: '):
        out += ['Homepage: https://sparkylinux.org', 'Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues']
    else:
        out.append(line)
binaries = (here / 'debian-qt5' / 'binaries.control').read_text().strip()
# the Qt 5 settings library's catalogue is in Debian's liboxygenstyleconfig-data since 4:6.6.3-1
binaries = re.sub(r'(Package: liboxygenstyleconfig5-6\n(?:.*\n)*?Depends: )', r'\1liboxygenstyleconfig-data,\n         ', binaries, count=1)
assert 'liboxygenstyleconfig-data' in binaries
control.write_text('\n'.join(out) + '\n\n' + binaries + '\n')
rules = Path('debian/rules')
text = rules.read_text()
assert text.count('-DBUILD_QT5=OFF') == 1
rules.write_text(text.replace('-DBUILD_QT5=OFF', '-DBUILD_QT5=ON -DBUILD_QT6=OFF'))
PY
grep -q -- '-DBUILD_QT5=ON -DBUILD_QT6=OFF' debian/rules
test "$(grep -c '^Package: ' debian/control)" = 3
dch --package oxygen-qt5 --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'Sparky Stereo OS (queue row 59): the Qt 5 Oxygen style that Debian stopped building in 4:6.6.3-1 and KDE still builds: KDE oxygen 6.7.4 with BUILD_QT5=ON and BUILD_QT6=OFF, as source oxygen-qt5, with the three Qt 5 packages of Debian 4:6.5.4-1; the settings catalogue comes from liboxygenstyleconfig-data.'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
cd "$BUILD_ROOT"
dpkg-source -b authored
cp "$BUILD_ROOT"/oxygen-qt5_*.dsc "$BUILD_ROOT"/oxygen-qt5_*.debian.tar.* "$BUILD_ROOT"/oxygen-qt5_6.7.4.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/oxygen-qt5_${V}.dsc" "$BUILD_ROOT/lean-source"
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare "$BUILD_ROOT/lean-source" "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
cd "$BUILD_ROOT/lean-source"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc -j"${JOBS:-4}"
# the stage is the source closure, in one folder: the archives, the .dsc and every file it names, the buildinfo and the changes
cp "$BUILD_ROOT"/*+lc1_*.deb "$BUILD_ROOT"/*+lc1.dsc "$BUILD_ROOT"/*+lc1.debian.tar.* "$BUILD_ROOT"/oxygen-qt5_6.7.4.orig.tar.* \
	"$BUILD_ROOT"/*+lc1_*.buildinfo "$BUILD_ROOT"/*+lc1_*.changes "$OUT/"
(cd "$OUT" && PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs ./*.deb)
cp .sparky-lc/source.json "$OUT/native-source.json"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
