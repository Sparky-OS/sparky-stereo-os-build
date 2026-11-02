#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-problems-plasma (ORDER 350): the session's notifier of sparky-stereo-problems. CMake against
# KDE Frameworks and the engine's library (sparky-stereo-problems, its pkg-config file), then the source package,
# provenance and Lean Code's build-tree.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
PACKAGE=sparky-stereo-problems-plasma
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.problems-plasma.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
strip --strip-unneeded "$D/usr/bin/sparky-stereo-problems-notifier"
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
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -l"$PRIVATE" --ignore-missing-info -O "$D/usr/bin/sparky-stereo-problems-notifier" 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
[ -n "$SHLIBS" ] || { echo "dpkg-shlibdeps found no dependencies" >&2; exit 1; }
ENGINE=$(pkg-config --modversion sparky-stereo-problems)
DEPENDS="$SHLIBS, sparky-stereo-problems (>= $ENGINE), pkexec, kdialog"
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
Description: the computer's problems as notifications in Plasma
  The session's side of sparky-stereo-problems: every problem the computer
  keeps, the machine's, this boot's and the person's own, as a KDE
  notification at login and whenever one is kept or changes, with Show
  details, Repair (through pkexec for the machine's problems), the problem's
  own actions and Hide, in the person's language.
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
Build-Depends: cmake, dpkg-dev, extra-cmake-modules, g++, gettext, libkf6i18n-dev, libkf6notifications-dev, pkgconf, qt6-base-dev, sparky-stereo-problems (>= 0.1.0)
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: $PACKAGE
Architecture: amd64
Depends: \${shlibs:Depends}, sparky-stereo-problems (>= 0.1.0), pkexec, kdialog
Description: the computer's problems as notifications in Plasma
 Every problem sparky-stereo-problems keeps, as a KDE notification with Show
 details, Repair, the problem's own actions and Hide.
EOC
{
	printf '%s (%s) unstable; urgency=medium\n\n' "$PACKAGE" "$VERSION"
	sed -n '4,/^---/p' "$HERE/CHANGELOG" | grep -v '^---'
	printf '\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 -0300\n'
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
(cd "$WORK" && dpkg-source -b "$S" >/dev/null)
cp "$WORK/${PACKAGE}_${VERSION}.dsc" "$WORK/${PACKAGE}_${VERSION}.tar.xz" "$OUT/"

"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
sync
