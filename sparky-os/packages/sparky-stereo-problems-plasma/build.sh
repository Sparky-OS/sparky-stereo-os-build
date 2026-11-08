#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-problems-plasma (ORDER 350): the session's notifier of sparky-stereo-problems and (ORDER 468) the
# Problems page of System Settings. CMake against KDE Frameworks and the engine's library (sparky-stereo-problems, its pkg-config file), then the source package,
# provenance and Lean Code's build-tree.
# Last update 2026/11/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
OUT=${OUT:?Set OUT to the workspace output directory}
PACKAGE=sparky-stereo-problems-plasma
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.problems-plasma.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DKDE_INSTALL_LIBDIR=lib/x86_64-linux-gnu -DBUILD_TESTING=OFF >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
strip --strip-unneeded "$D/usr/bin/sparky-stereo-problems-notifier" "$D"/usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/kcms/systemsettings/kcm_sparkystereo_problems.so
# the session's side: at login and whenever a problem is kept or changes
mkdir -p "$D/usr/lib/systemd/user/graphical-session.target.wants"
for u in sparky-stereo-problems-notifier.path sparky-stereo-problems-notifier.service; do
	ln -s ../$u "$D/usr/lib/systemd/user/graphical-session.target.wants/$u"
done
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
# the engine's library is private to sparky-stereo-problems, named below
PRIVATE=$(pkg-config --variable=libdir sparky-stereo-problems)
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -l"$PRIVATE" --ignore-missing-info -O "$D/usr/bin/sparky-stereo-problems-notifier" "$D"/usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/kcms/systemsettings/kcm_sparkystereo_problems.so 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
[ -n "$SHLIBS" ] || { echo "dpkg-shlibdeps found no dependencies" >&2; exit 1; }
ENGINE=$(pkg-config --modversion sparky-stereo-problems)
DEPENDS="$SHLIBS, sparky-stereo-problems (>= $ENGINE), pkexec, kdialog, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, qml6-module-qtquick-controls, qml6-module-qtquick-layouts"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOC
Package: $PACKAGE
Version: $VERSION
Architecture: amd64
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: kde
Priority: optional
Homepage: https://sparkylinux.org
Description: the computer's problems as notifications and a Problems page in Plasma
  The session's side of sparky-stereo-problems: every problem the computer
  keeps, the machine's, this boot's and the person's own, as a KDE
  notification at login and whenever one is kept or changes, with Show
  details, Repair (through pkexec for the machine's problems), the problem's
  own actions and Dismiss; and the Problems page of System Settings, which
  lists the current and the dismissed problems and brings one back, in the
  person's language.
EOC
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)

S=$WORK/$PACKAGE-$VERSION
mkdir -p "$S/debian/source"
cp -a "$HERE/." "$S/"
cat >"$S/debian/control" <<EOC
Source: $PACKAGE
Section: kde
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Standards-Version: 4.7.3
Build-Depends: cmake, dpkg-dev, extra-cmake-modules, g++, gettext, libkf6coreaddons-dev, libkf6i18n-dev, libkf6kcmutils-dev, libkf6notifications-dev, pkgconf, qt6-base-dev, qt6-declarative-dev, sparky-stereo-problems (>= 0.2.0)
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, sparky-stereo-problems (>= 0.2.0), pkexec, kdialog, qml6-module-org-kde-kcmutils, qml6-module-org-kde-kirigami, qml6-module-qtquick-controls, qml6-module-qtquick-layouts
Description: the computer's problems as notifications and a Problems page in Plasma
 Every problem sparky-stereo-problems keeps, as a KDE notification with Show
 details, Repair, the problem's own actions and Dismiss, and the Problems
 page of System Settings with the current and the dismissed ones.
EOC
{
	printf '%s (%s) unstable; urgency=medium\n\n' "$PACKAGE" "$VERSION"
	sed -n '4,/^---/p' "$HERE/CHANGELOG" | grep -v '^---'
	printf '\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sun, 08 Nov 2026 12:00:00 -0300\n'
} >"$S/debian/changelog"
cp "$HERE/copyright" "$S/debian/copyright"
echo '3.0 (native)' >"$S/debian/source/format"
cat >"$S/debian/rules" <<'EOC'
#!/usr/bin/make -f
binary:
	OUT=$(CURDIR)/.. bash ./build.sh
	dpkg-distaddfile $$(dpkg-parsechangelog -S Source)_$$(dpkg-parsechangelog -S Version)_amd64.deb kde optional
clean:
build:
EOC
chmod +x "$S/debian/rules"
# A native package is dated by its own newest changelog entry (ORDER 421b); the tree is normalized so the checkout time and the umask stay out
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" changelog "$S/debian/changelog")}
export SOURCE_DATE_EPOCH
python3 "$REPRO" normalize "$SOURCE_DATE_EPOCH" "$S"
(cd "$WORK" && dpkg-source -b "$S" >/dev/null)
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"

"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
sync
