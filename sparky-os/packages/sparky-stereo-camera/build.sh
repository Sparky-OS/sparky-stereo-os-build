#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/15
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0
PACKAGE=sparky-stereo-camera
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.camera.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# Build from the same tracked inputs that enter the source archive.
TOOLKIT=$(cd "$HERE/../.." && pwd)
COPY="$HERE/build-tools/copy-recipe.py"
[ -f "$COPY" ] || COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$WORK/inputs"
mkdir -p "$WORK/inputs/build-tools"
cp "$COPY" "$WORK/inputs/build-tools/"
HERE=$WORK/inputs
D=$WORK/$PACKAGE
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DKDE_INSTALL_LIBDIR=lib/x86_64-linux-gnu -DKDE_INSTALL_LIBEXECDIR=lib/x86_64-linux-gnu/libexec -DBUILD_TESTING=OFF -DKDE_INSTALL_USE_QT_SYS_PATHS=ON >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
find "$D" -name '*.so' -o -path '*/bin/sparky-stereo-camera' | xargs strip --strip-unneeded
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/CHANGELOG" "$D/usr/share/doc/$PACKAGE/CHANGELOG"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O $(find "$D" -type f \( -name '*.so' -o -path '*/bin/sparky-stereo-camera' \)) 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
EXTRA_DEPENDS="pipewire-bin, wireplumber, systemsettings, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d15~), qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window"
DEPENDS="$SHLIBS, pipewire-bin, wireplumber, systemsettings, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, qml6-module-qtmultimedia (>= 6.11.2-3+stereo3d15~), qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Camera page for System Settings
  The default camera, the picture format and size, the camera's own controls,
  a live preview and the packing of a two-lens camera; kept across a re-plug.
EOF
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_amd64.deb"

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
COPY="$HERE/build-tools/copy-recipe.py"
[ -f "$COPY" ] || COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$S"
mkdir -p "$S/build-tools"
cp "$COPY" "$S/build-tools/"
cat >"$S/debian/control" <<EOF
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: git, python3, cmake, dpkg-dev, extra-cmake-modules, g++, gettext, libkf6coreaddons-dev, libkf6i18n-dev, libkf6kcmutils-dev, libpipewire-0.3-dev, libspa-0.2-dev, pkgconf, qt6-base-dev, qt6-declarative-dev, qt6-multimedia-dev
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, $EXTRA_DEPENDS
Description: Camera page for System Settings
 The default camera, the picture format and size, the camera's own controls,
 a live preview and the packing of a two-lens camera; kept across a re-plug.
EOF
cat >"$S/debian/changelog" <<EOF
$PACKAGE ($VERSION) unstable; urgency=medium

  * First release (ORDER 570): the Camera page of System Settings, its command and the user service that applies the saved choices.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sun, 15 Nov 2026 12:00:00 -0300
EOF
cp "$HERE/copyright" "$S/debian/copyright"
mkdir -p "$S/debian/source"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOF'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_amd64.deb System optional
clean:
build:
EOF
chmod +x "$S/debian/rules"
# A native package is dated by its own newest changelog entry (ORDER 421b); the tree is normalized so the checkout time and the umask stay out
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" changelog "$S/debian/changelog")}
export SOURCE_DATE_EPOCH
python3 "$REPRO" normalize "$SOURCE_DATE_EPOCH" "$S"
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
