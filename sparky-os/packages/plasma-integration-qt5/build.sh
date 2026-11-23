#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Plasma's platform theme for Qt 5 programs, so that a Qt 5 program follows the person's choices in
# System Settings (Application Style, colours, fonts, icons, KDE's file dialog) as Qt 6 programs do (queue row 59; Daniel,
# 2026-10-08: "with our defaults we are prone to make, at least most of the users, happy out of the box, and for the
# other ... personalization is there"). Without it a Qt 5 program in a Plasma 6 session takes Qt 5's own KDE theme, which
# does not read Plasma 6's setting: with the Oxygen style for Qt 5 installed it keeps Oxygen after the person picks Fusion.
# KDE still builds it: plasma/plasma-integration keeps option(BUILD_QT5 "Build for Qt5" ON) at v6.7.4. Debian's
# plasma-integration 6.6.3-1 dropped it ("Drop Qt5/KF5 support", Aurélien Couderc); plasma5-integration 6.5.4-2 left
# unstable on 2026-04-08 as "[auto-cruft] NBS (no longer built by plasma-integration, no reverse dependencies)"; trixie
# still has 6.3.6-1+b3.
# This source, plasma-integration-qt5, is KDE's plasma-integration 6.7.4 release (Debian's orig tarball, KDE's signature
# beside it) with Debian's 6.7.4-1 packaging reduced to the plasma5-integration package of Debian's 6.5.4-2 (its stanza; the
# Qt 5 and common build dependencies of 6.5.4-2), built with BUILD_QT5=ON and BUILD_QT6=OFF. Upstream installs the
# translations only in its Qt 6 block, and Debian's plasma-integration ships them (it Breaks and Replaces
# plasma5-integration below 6.5.90 for that), so this package installs the plugin alone; the Qt 5 plugin carries no
# translation domain of its own (Debian's 6.5.4-2 build has none either). The edition's own plasma-integration
# (+stereo3dN, packages/plasma-integration) and Debian's stay untouched: no file is shared with either. Lean Code at +lc1.
# Run inside a clean distribution build container with the packages of ./build-depends installed.
# SOURCE_DSC names Debian's unmodified plasma-integration_6.7.4-1.dsc and its adjacent archives.
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
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian plasma-integration_6.7.4-1.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS="parallel=${JOBS:-4}"
export LC_ALL=C.UTF-8
# above 6.5.4-2 and 6.3.6-1+b3, the last binaries a machine can have, and at or above 6.5.90, where Debian's
# plasma-integration stops breaking plasma5-integration
VERSION=6.7.4-1+sparky1
V=${VERSION#*:}
SRC=$(dirname "$SOURCE_DSC")
printf '%s  %s\n' 1a6f4f21f3191a3cc7bed97b096a40b4e1e465b98c61c0977d4fa5a718747f25 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/authored" ]
mkdir -p "$BUILD_ROOT" "$OUT/authored"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/debian-plasma-integration"
# the same upstream tarball under this source's name, KDE's signature beside it
cp "$SRC/plasma-integration_6.7.4.orig.tar.xz" "$BUILD_ROOT/plasma-integration-qt5_6.7.4.orig.tar.xz"
cp "$SRC/plasma-integration_6.7.4.orig.tar.xz.asc" "$BUILD_ROOT/plasma-integration-qt5_6.7.4.orig.tar.xz.asc"
mkdir "$BUILD_ROOT/authored"
tar -C "$BUILD_ROOT/authored" --strip-components=1 -xf "$BUILD_ROOT/plasma-integration-qt5_6.7.4.orig.tar.xz"
cp -a "$BUILD_ROOT/debian-plasma-integration/debian" "$BUILD_ROOT/authored/debian"
cd "$BUILD_ROOT/authored"
rm debian/plasma-integration.install
cp "$HERE"/debian-qt5/plasma5-integration.install debian/
python3 - "$HERE" <<'PY'
import sys
from pathlib import Path
here = Path(sys.argv[1])
control = Path('debian/control')
source = control.read_text().split('\n\n')[0]
out = []
skip = False
for line in source.splitlines():
    if skip and line[:1] in (' ', '\t'):
        continue
    skip = False
    if line.startswith('Source: '):
        out.append('Source: plasma-integration-qt5')
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
assert binaries.startswith('Package: plasma5-integration\n')
control.write_text('\n'.join(out) + '\n\n' + binaries + '\n')
rules = Path('debian/rules')
text = rules.read_text()
assert text.count('-DBUILD_QT5=OFF') == 1
rules.write_text(text.replace('-DBUILD_QT5=OFF', '-DBUILD_QT5=ON -DBUILD_QT6=OFF'))
PY
grep -q -- '-DBUILD_QT5=ON -DBUILD_QT6=OFF' debian/rules
test "$(grep -c '^Package: ' debian/control)" = 1
dch --package plasma-integration-qt5 --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'Sparky Stereo OS (queue row 59): the Qt 5 platform theme that Debian stopped building in 6.6.3-1 and KDE still builds: KDE plasma-integration 6.7.4 with BUILD_QT5=ON and BUILD_QT6=OFF, as source plasma-integration-qt5, with the plasma5-integration package of Debian 6.5.4-2; the translations stay with plasma-integration.'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
cd "$BUILD_ROOT"
dpkg-source -b authored
cp "$BUILD_ROOT"/plasma-integration-qt5_*.dsc "$BUILD_ROOT"/plasma-integration-qt5_*.debian.tar.* \
	"$BUILD_ROOT"/plasma-integration-qt5_6.7.4.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/plasma-integration-qt5_${V}.dsc" "$BUILD_ROOT/lean-source"
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare "$BUILD_ROOT/lean-source" "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
cd "$BUILD_ROOT/lean-source"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc -j"${JOBS:-4}"
# the stage is the source closure, in one folder: the archives, the .dsc and every file it names, the buildinfo and the changes
cp "$BUILD_ROOT"/*+lc1_*.deb "$BUILD_ROOT"/*+lc1.dsc "$BUILD_ROOT"/*+lc1.debian.tar.* "$BUILD_ROOT"/plasma-integration-qt5_6.7.4.orig.tar.* \
	"$BUILD_ROOT"/*+lc1_*.buildinfo "$BUILD_ROOT"/*+lc1_*.changes "$OUT/"
(cd "$OUT" && PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs ./*.deb)
cp .sparky-lc/source.json "$OUT/native-source.json"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
