#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-integration (hand-assembled .deb, Paweł's formula): the runner of the edition's integration packs,
# with the pack generator's source (make-pack.py) retained in the source package for the packs that follow its format.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the output directory}
VERSION=0.1.2+lc1
PKG=sparky-stereo-integration
mkdir -p "$OUT"
W=$(mktemp -d "$OUT/.$PKG.XXXXXX")
trap 'rm -rf "$W"' EXIT
RECIPE=$HERE
COPY="$RECIPE/../../../tools/copy-recipe.py"
python3 "$COPY" "$RECIPE" "$W/authoring"
mkdir -p "$W/authoring/build-tools"
cp "$COPY" "$W/authoring/build-tools/"
HERE=$W/authoring
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/etc/xdg/autostart" "$D/usr/share/sparky/$PKG" "$D/usr/share/sparky-stereo/integrations.d" "$D/usr/share/doc/$PKG" "$D/usr/lib/sparky-stereo" "$D/usr/share/krunner/dbusplugins" "$D/usr/share/dbus-1/services"
install -m755 "$HERE/bin/sparky-stereo-integration" "$D/usr/bin/"
install -m755 "$HERE/krunner/missing-program" "$D/usr/lib/sparky-stereo/krunner-missing-program"
install -m644 "$HERE/share/sparky-stereo-missing-program.desktop" "$D/usr/share/krunner/dbusplugins/"
install -m644 "$HERE/share/org.sparky.stereo.MissingProgram.service" "$D/usr/share/dbus-1/services/"
install -m644 "$HERE/share/sparky-stereo-integrationrc" "$D/etc/xdg/"
install -m644 "$HERE/share/sparky-stereo-integration-sync.desktop" "$D/etc/xdg/autostart/"
install -m644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
echo /etc/xdg/sparky-stereo-integrationrc >"$D/DEBIAN/conffiles"
echo /etc/xdg/autostart/sparky-stereo-integration-sync.desktop >>"$D/DEBIAN/conffiles"
cat >"$D/DEBIAN/postinst" <<'X'
#!/bin/sh
# command-not-found's index is filled by its own apt update hook (/etc/apt/apt.conf.d/50command-not-found); here it is
# filled at once from the package lists apt already has, when it is still empty
set -e
if [ "$1" = configure ] && [ ! -s /var/lib/command-not-found/commands.db ] && command -v update-command-not-found >/dev/null; then
	update-command-not-found || true
fi
exit 0
X
chmod 755 "$D/DEBIAN/postinst"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<X
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: bash, command-not-found (>= 23.04.0-3+sparky1), kdialog, python3, python3-dbus, python3-gi
Recommends: pkexec
Section: Utilities
Priority: optional
Homepage: https://sparkylinux.org
Description: Runs the Dolphin right click actions of the stereo integration packs
  Runs the actions of the edition's integration packs. When the program an action needs is missing, it runs command-not-found and offers the
  package it names, with its own message; hiding such actions is a secondary choice after Cancel.
X
(cd "$D" && find usr etc -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
A=$HERE
PYTHONPATH="$RECIPE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$A"
sync
