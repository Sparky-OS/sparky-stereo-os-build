#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0
PACKAGE=sparky-stereo-cec
ARCH=$(dpkg --print-architecture)
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.sparky-stereo-cec.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/payload
cmake -S "$HERE" -B "$W/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build "$W/build" -j4
DESTDIR="$D" cmake --install "$W/build" --prefix /usr
strip "$D/usr/bin/$PACKAGE"
install -Dm644 "$HERE/share/sparky-stereo-cec.desktop" "$D/etc/xdg/autostart/sparky-stereo-cec.desktop"
install -Dm644 "$HERE/share/70-sparky-stereo-cec.rules" "$D/usr/lib/udev/rules.d/70-sparky-stereo-cec.rules"
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
mkdir -p "$W/debian" "$D/DEBIAN"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PACKAGE" "$PACKAGE" >"$W/debian/control"
shlib_options=()
if [[ -n ${SHLIBS_FILE:-} ]]; then shlib_options+=("-L$SHLIBS_FILE"); fi
if [[ -n ${SHLIBS_DIRECTORY:-} ]]; then shlib_options+=("-l$SHLIBS_DIRECTORY"); fi
DEPS=$(cd "$W" && dpkg-shlibdeps -O "${shlib_options[@]}" -e"$D/usr/bin/$PACKAGE")
DEPS=${DEPS#shlibs:Depends=}
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<CONTROL
Package: $PACKAGE
Version: $VERSION
Architecture: $ARCH
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPS, qt6-wayland, v4l-utils (>= 1.32)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: TV power follows Plasma output power
  Send HDMI-CEC standby and wake messages for matched Plasma Wayland outputs.
  The user's active KDE session controls the helper; no idle timer is added.
CONTROL
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz -b "$D" "$OUT/${PACKAGE}_${VERSION}_${ARCH}.deb"
S=$W/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<CONTROL
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: cmake, dpkg-dev, g++, libkf6config-dev, libkscreen-dev, qt6-base-dev, qt6-wayland-dev
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: any
Depends: \${shlibs:Depends}, qt6-wayland, v4l-utils (>= 1.32)
Description: TV power follows Plasma output power
 Send HDMI-CEC standby and wake messages for matched Plasma Wayland outputs.
CONTROL
cat >"$S/debian/changelog" <<CHANGELOG
$PACKAGE ($VERSION) unstable; urgency=medium

  * Follow native Plasma output power for matched CEC televisions.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 08 Oct 2026 13:15:00 -0300
CHANGELOG
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'RULES'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_$$(dpkg --print-architecture).deb System optional
clean:
build:
RULES
chmod +x "$S/debian/rules"
(cd "$W" && dpkg-source -b "$S")
cp "$W/${PACKAGE}_${VERSION}.dsc" "$W/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
