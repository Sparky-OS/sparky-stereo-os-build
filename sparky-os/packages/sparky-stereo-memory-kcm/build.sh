#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.6
PACKAGE=sparky-stereo-memory-kcm
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.memory-kcm.XXXXXX")
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
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DKDE_INSTALL_LIBDIR=lib/x86_64-linux-gnu -DKDE_INSTALL_LIBEXECDIR=lib/x86_64-linux-gnu/libexec -DBUILD_TESTING=OFF >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
find "$D" -name '*.so' -o -path '*/kauth/sparkystereo_memory_helper' | xargs strip --strip-unneeded
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/CHANGELOG" "$D/usr/share/doc/$PACKAGE/CHANGELOG"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O $(find "$D" -type f \( -name '*.so' -o -path '*/kauth/*' \)) 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
DEPENDS="$SHLIBS, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, sparky-stereo-kernel-settings (>= 20261010.2~sparky9~0), sparky-stereo-problems (>= 0.1.0), sparky-aptus-stereo-appcenter (>= 0.1.0), pkexec"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOF
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Recommends: sparky-stereo-cushion-swap
Breaks: sparky-stereo-kernel-settings (<< 20261103.4~)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Memory page for System Settings
  The Cushion Swap File: its switch, its protection state, kept problems
  and how it is woken.
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
Build-Depends: git, python3, cmake, dpkg-dev, extra-cmake-modules, g++, libkf6auth-dev, libkf6coreaddons-dev, libkf6i18n-dev, libkf6kcmutils-dev, qt6-base-dev, qt6-declarative-dev
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, sparky-stereo-kernel-settings (>= 20261010.2~sparky9~0), sparky-stereo-problems (>= 0.1.0), sparky-aptus-stereo-appcenter (>= 0.1.0), pkexec
Recommends: sparky-stereo-cushion-swap
Breaks: sparky-stereo-kernel-settings (<< 20261103.4~)
Description: Memory page for System Settings
 The Cushion Swap File and its protection state in System Settings.
EOF
cat >"$S/debian/changelog" <<EOF
$PACKAGE ($VERSION) unstable; urgency=medium

  * Remove zram controls, backend and translations; retain Cushion Swap.
  * Leave the administrator-owned zram configuration untouched.
  * Break older kernel-settings which can still enable zram.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 12:00:00 -0300

$PACKAGE (0.1.5) unstable; urgency=medium

  * Copy only tracked recipe inputs; retain the shared copier for source rebuilds.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Tue, 03 Nov 2026 12:00:00 -0300

$PACKAGE (0.1.4) unstable; urgency=medium

  * Show memory protection, unreadable status and localized kept problems.
  * Offer the shared engine's authorized repair and retain unsaved choices.
  * Translate status, repairs and structured zram decisions in nine languages.
  * Prefer engine text, label raw daemon words and keep the action order stable.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 16:00:00 -0300

$PACKAGE (0.1.3) unstable; urgency=medium

  * German, Japanese, Korean, Polish, Brazilian Portuguese, Simplified
    Chinese and Traditional Chinese strings for the page metadata and
    the KAuth action.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 29 Oct 2026 22:00:00 -0300

$PACKAGE (0.1.2) unstable; urgency=medium

  * German, Japanese, Korean, Polish, Brazilian Portuguese, Simplified
    Chinese and Traditional Chinese strings for the page.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Thu, 29 Oct 2026 19:30:00 -0300

$PACKAGE (0.1.1) unstable; urgency=medium

  * French strings for the page and the KAuth actions.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 12 Oct 2026 00:00:00 -0300

$PACKAGE (0.1.0) unstable; urgency=medium

  * First release: the Memory page, saved through KAuth.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 10 Oct 2026 19:00:00 -0300
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
(cd "$WORK" && dpkg-source -b "$S")
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"
sync
