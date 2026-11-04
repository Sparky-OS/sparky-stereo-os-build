#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/04
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.6+lc1
PACKAGE=sparky-stereo-cec
COPY=${COPY_RECIPE:-$HERE/../../../tools/copy-recipe.py}
TOOLKIT=$(cd "$HERE/../.." && pwd)
SOURCE_PACKAGE=${SOURCE_PACKAGE:-yes}
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
# what fails is kept by the edition's one engine and shown in the session (ORDER 346f-1): the messages as journal catalogs
mkdir -p "$D/usr/lib/systemd/catalog"
sparky-stereo-problems catalog "$PACKAGE" "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1
mkdir -p "$W/debian" "$D/DEBIAN"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$PACKAGE" "$PACKAGE" >"$W/debian/control"
shlib_options=()
if [[ -n ${SHLIBS_FILE:-} ]]; then shlib_options+=("-L$SHLIBS_FILE"); fi
if [[ -n ${SHLIBS_DIRECTORY:-} ]]; then shlib_options+=("-l$SHLIBS_DIRECTORY"); fi
PRIVATE=$(pkg-config --variable=libdir sparky-stereo-problems)
DEPS=$(cd "$W" && dpkg-shlibdeps -O -l"$PRIVATE" --ignore-missing-info "${shlib_options[@]}" -e"$D/usr/bin/$PACKAGE")
DEPS=${DEPS#shlibs:Depends=}
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<CONTROL
Package: $PACKAGE
Version: $VERSION
Architecture: $ARCH
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPS, qt6-wayland, v4l-utils (>= 1.32), sparky-stereo-problems (>= 0.1.2), sparky-stereo-problems-plasma (>= 0.1.0)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: TV power follows Plasma output power
  Send HDMI-CEC standby and wake messages for matched Plasma Wayland outputs.
  The user's active KDE session controls the helper; no idle timer is added.
  A TV that does not answer, an adapter that cannot be used and a session that
  cannot be found are kept by sparky-stereo-problems and shown in the session.
CONTROL
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
if [ "$1" = remove ] && command -v sparky-stereo-problems >/dev/null 2>&1; then
    sparky-stereo-problems clear --all sparky-stereo-cec
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postrm"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
"$TOOLKIT/repo/provenance.sh" --tree "$D"
PYTHONPATH="$TOOLKIT${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
[ "$SOURCE_PACKAGE" = yes ] || exit 0
S=$W/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
python3 "$COPY" "$HERE" "$S"
mkdir -p "$S/build-tools"
cp "$COPY" "$S/build-tools/"
cat >"$S/debian/control" <<CONTROL
Source: $PACKAGE
Section: System
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: git, python3, cmake, dpkg-dev, g++, pkgconf, libkf6config-dev, libkscreen-dev, qt6-base-dev, qt6-declarative-dev, qt6-wayland-dev, sparky-stereo-problems (>= 0.1.2)
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: any
Depends: \${shlibs:Depends}, qt6-wayland, v4l-utils (>= 1.32), sparky-stereo-problems (>= 0.1.2), sparky-stereo-problems-plasma (>= 0.1.0)
Description: TV power follows Plasma output power
 Send HDMI-CEC standby and wake messages for matched Plasma Wayland outputs.
CONTROL
cat >"$S/debian/changelog" <<CHANGELOG
$PACKAGE ($VERSION) unstable; urgency=medium

  * Keep a TV that does not answer, an adapter without a usable address, a cec-ctl
    that cannot start and a login session that cannot be found with
    sparky-stereo-problems, shown in the session and cleared when the TV
    answers again (ORDER 346f-1). A refusal to power another active input
    stays a notice.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Wed, 04 Nov 2026 02:00:00 +0000

$PACKAGE (0.1.5) unstable; urgency=medium

  * Copy only tracked recipe inputs; retain the shared copier for source rebuilds.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 10:00:00 +0000

$PACKAGE (0.1.4) unstable; urgency=medium

  * The autostart entry's name in German, French, Japanese, Korean,
    Simplified Chinese and Traditional Chinese.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Fri, 30 Oct 2026 01:50:00 +0000

$PACKAGE (0.1.1) unstable; urgency=medium

  * Follow native Plasma output power for matched CEC televisions.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 08 Oct 2026 13:15:00 -0300
CHANGELOG
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'RULES'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. COPY_RECIPE=$(CURDIR)/build-tools/copy-recipe.py SOURCE_PACKAGE=no bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_$$(dpkg --print-architecture).deb System optional
clean:
build:
RULES
chmod +x "$S/debian/rules"
(cd "$W" && dpkg-source -b "$S")
cp "$W/${PACKAGE}_${VERSION}.dsc" "$W/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
