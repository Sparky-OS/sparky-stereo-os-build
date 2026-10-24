#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.2.2
PACKAGE=sparky-stereo-graphics
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.graphics.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
cmake -S "$HERE" -B "$WORK/build" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DKDE_INSTALL_LIBDIR=lib/x86_64-linux-gnu -DKDE_INSTALL_LIBEXECDIR=lib/x86_64-linux-gnu/libexec -DBUILD_TESTING=OFF >"$WORK/configure.log"
cmake --build "$WORK/build" -j"${JOBS:-4}" >"$WORK/build.log"
DESTDIR=$D cmake --install "$WORK/build" >"$WORK/install.log"
find "$D" -name '*.so' -o -path '*/usr/bin/sparky-stereo-gpu-env' -o -path '*/usr/bin/sparky-stereo-gpu-record' | xargs strip --strip-unneeded
# the boot service is on from the start, as the edition's other services are
mkdir -p "$D/usr/lib/systemd/system/multi-user.target.wants"
ln -s ../sparky-stereo-gpu-record.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-gpu-record.service"
install -Dm644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/DEBIAN" "$WORK/shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: amd64\n' "$PACKAGE" "$PACKAGE" >"$WORK/shlibs/debian/control"
SHLIBS=$(cd "$WORK/shlibs" && dpkg-shlibdeps -O $(find "$D" -type f \( -name '*.so' -o -path '*/usr/bin/sparky-stereo-gpu-env' -o -path '*/usr/bin/sparky-stereo-gpu-record' \)) 2>/dev/null | sed -n 's/^shlibs:Depends=//p')
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
  desktop and where players, games, browsers and other programs draw, and
  edits KDE's own per-program setting. Automatic puts players, games and any
  program started in 3D on the GPU measured best on the machine whatever the
  power profile, browsers by the power profile, and other programs on the GPU
  that draws the desktop. Also the copy-back choice of
  hardware video decoding, the GPU power switches of power-profiles-daemon,
  and the machine record shipped for measured models.
EOS
printf '%s\n' /etc/xdg/plasma-workspace/env/sparky-stereo-graphics.sh >"$D/DEBIAN/conffiles"
# The machine record (/etc/xdg/sparky-stereo-graphicsrc) is written by sparky-stereo-gpu-record, never shipped:
# at boot from the record of a known model, or by a measurement or an administrator on this machine.
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ]; then
	sparky-stereo-gpu-record --apply-known >/dev/null 2>&1 || true
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
	fi
fi
exit 0
EOS
cat >"$D/DEBIAN/prerm" <<'EOS'
#!/bin/sh
# prerm script
set -e
if [ "$1" = "remove" ]; then
	# a record from a shipped model goes with the shipped records; one made on this machine stays
	sparky-stereo-gpu-record --apply-known --machines /nonexistent >/dev/null 2>&1 || true
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
f=/etc/xdg/sparky-stereo-graphicsrc
if [ "$1" = "purge" ] && [ -f "$f" ] && grep -q '^Origin=' "$f"; then
	# the keys sparky-stereo-gpu-record wrote; anything an administrator added stays
	awk '
		/^\[/ { group = $0; held = $0; shown = 0; next }
		group == "[Measured]" || group == "[Record]" { next }
		group == "[Decoding]" && /^CopyBack(\[\$i\])?=/ { next }
		/^[[:space:]]*$/ { next }
		{ if (!shown && held != "") { print held; shown = 1 } print }
	' "$f" >"$f.dpkg-new"
	if [ -s "$f.dpkg-new" ]; then mv "$f.dpkg-new" "$f"; else rm -f "$f" "$f.dpkg-new"; fi
fi
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || true
	fi
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
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
 Every graphics processor, the main desktop GPU, where programs draw, the GPU
 measured best for players and 3D, and the copy-back choice of video decoding.
EOS
cat >"$S/debian/changelog" <<EOS
$PACKAGE ($VERSION) unstable; urgency=medium

  * Automatic split by kind (Daniel, 2026-10-24): players, games and any
    program started in 3D on the GPU measured best whatever the power
    profile; browsers by the power profile; other programs on the GPU that
    draws the desktop in every profile.
  * PrefersNonDefaultGPU=true means what KDE's launcher does with it: the
    first discrete GPU, nothing when the default GPU is discrete; the page
    calls it "The dedicated GPU".
  * An audio program without video counts as another program.
  * From an NVIDIA desktop to a Mesa GPU, name Mesa's EGL and GLX vendors.
  * sparky-stereo-gpu-run keeps a GPU its caller already chose.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 24 Oct 2026 04:03:00 -0300

$PACKAGE (0.2.1) unstable; urgency=medium

  * sparky-stereo-gpu-env --app also takes the path of a desktop file outside
    the menu (a launcher on the desktop), as Plasma's launcher (kf6-kio
    6.30.0-1+stereo3d6) asks for such a program.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 24 Oct 2026 03:25:00 -0300

$PACKAGE (0.2.0) unstable; urgency=medium

  * Automatic puts players, and any program started in 3D, on the GPU
    measured best on the machine whatever the power profile, battery
    included; the power profile keeps steering games, browsers and other
    programs; "Follow the power profile" is a choice on every kind.
  * The machine record in /etc/xdg/sparky-stereo-graphicsrc, the file
    libmedia-gpu-route reads: sparky-stereo-gpu-record writes it at boot for
    a known model (the Lenovo ideapad 310-15ABR, from ORDER 234's numbers),
    or from a measurement on the machine.
  * A "Copy decoded video back" choice on the page ([Decoding] CopyBack).
  * --3d for sparky-stereo-gpu-env and sparky-stereo-gpu-run.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 24 Oct 2026 12:00:00 -0300

$PACKAGE (0.1.0) unstable; urgency=medium

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
