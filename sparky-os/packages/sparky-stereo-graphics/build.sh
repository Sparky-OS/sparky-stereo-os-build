#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/23
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0
PACKAGE=sparky-stereo-graphics
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.graphics.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DKDE_INSTALL_LIBDIR=lib/x86_64-linux-gnu -DKDE_INSTALL_LIBEXECDIR=lib/x86_64-linux-gnu/libexec -DBUILD_TESTING=OFF >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
find "$D" -name '*.so' -o -path '*/usr/bin/sparky-stereo-gpu-env' | xargs strip --strip-unneeded
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O $(find "$D" -type f \( -name '*.so' -o -path '*/usr/bin/sparky-stereo-gpu-env' \)) 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
DEPENDS="$SHLIBS, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Recommends: hwdata, power-profiles-daemon, switcheroo-control
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Graphics page for System Settings
  Lists every graphics processor, lets the person choose which one draws the
  desktop and where players, games, browsers and other programs draw, with
  Automatic following the power profile, and edits KDE's own per-program
  setting. Also the GPU power switches of power-profiles-daemon.
EOS
printf '%s\n' /etc/xdg/plasma-workspace/env/sparky-stereo-graphics.sh >"$D/DEBIAN/conffiles"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<EOS
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: cmake, dpkg-dev, extra-cmake-modules, g++, gettext, libkf6config-dev, libkf6coreaddons-dev, libkf6i18n-dev, libkf6kcmutils-dev, libkf6service-dev, qt6-base-dev, qt6-declarative-dev
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami
Recommends: hwdata, power-profiles-daemon, switcheroo-control
Description: Graphics page for System Settings
 Every graphics processor, the main desktop GPU and where programs draw.
EOS
cat >"$S/debian/changelog" <<EOS
$PACKAGE ($VERSION) unstable; urgency=medium

  * First release: the Graphics page, the sparky-stereo-gpu-env command, the
    sparky-stereo-gpu-run wrapper and the Plasma session script for the main GPU.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Fri, 23 Oct 2026 18:00:00 -0300
EOS
cp "$HERE/copyright" "$S/debian/copyright"
mkdir -p "$S/debian/source"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOS'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_amd64.deb System optional
clean:
build:
EOS
chmod +x "$S/debian/rules"
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"

"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
sync
