#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
#
# Builds sparky-stereo-corectrl (hand assembled, Paweł's formula): CoreCtrl and LACT in the edition (queue rows 168 and 601).
#   build.sh OUTDIR
# SPARKY_BUILD_IMAGE names the build image: Debian testing with dpkg-dev, gcc, node-acorn, nodejs, perl, python3,
# python3-yaml and sparky-stereo-problems (its catalog verb makes the journal catalogues).
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
PKG=sparky-stereo-corectrl
VERSION=0.1.0+lc1
IMAGE=${SPARKY_BUILD_IMAGE:?set SPARKY_BUILD_IMAGE to the build image (see the header)}
# the host's facts for the build record, and the source date from the recipe's last commit (ORDER 394b, ORDER 421b)
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$IMAGE" "$HERE"
umask 022
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.corectrl.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PKG"
# the polkit rule of CoreCtrl's setup guide: a vendor rule, read with the administrator's own rules in /etc (polkit(8))
install -D -m 644 "$HERE/share/90-sparky-stereo-corectrl.rules" "$D/usr/share/polkit-1/rules.d/90-sparky-stereo-corectrl.rules"
# CoreCtrl at login, only where it is installed (TryExec, Desktop Application Autostart Specification 0.5, 2.2), in the
# system tray by its own setting (Qt reads /etc/xdg/corectrl/corectrl.ini after the person's own file)
install -D -m 644 "$HERE/share/org.corectrl.CoreCtrl.desktop" "$D/etc/xdg/autostart/org.corectrl.CoreCtrl.desktop"
install -D -m 644 "$HERE/share/corectrl.ini" "$D/etc/xdg/corectrl/corectrl.ini"
install -D -m 755 "$HERE/bin/knob-owner" "$D/usr/libexec/sparky-stereo-corectrl/knob-owner"
install -D -m 644 "$HERE/share/sparky-stereo-knob-owner.service" "$D/usr/lib/systemd/system/sparky-stereo-knob-owner.service"
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
# the package's sentences in the ten languages, as journal catalogues for the edition's one engine
# (the engine runs in a container: it is a package program)
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}catalog-$PKG" --ulimit core=1 --cpus "${CPUS:-4}" --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -v "$HERE/problems-lang":/lang:ro -v "$D":"$D" "$IMAGE" \
	sparky-stereo-problems catalog "$PKG" /lang "$D/usr/lib/systemd/catalog" --subject LOCAL1
for s in postinst prerm postrm; do
	install -m 755 "$HERE/debian-scripts/$s" "$D/DEBIAN/$s"
done
install -m 644 "$HERE/debian-scripts/triggers" "$D/DEBIAN/triggers"
printf '%s\n' /etc/xdg/autostart/org.corectrl.CoreCtrl.desktop /etc/xdg/corectrl/corectrl.ini >"$D/DEBIAN/conffiles"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: python3, python3-gi, gir1.2-glib-2.0, python3-yaml, systemd, init-system-helpers (>= 1.54~), sparky-stereo-problems (>= 0.2.4)
Enhances: corectrl, lact
Section: admin
Priority: optional
Homepage: https://sparkylinux.org
Description: CoreCtrl and LACT in Sparky Stereo OS: no password, the tray, one writer per setting
 Where CoreCtrl is installed, its helper starts without a password for an
 administrator at the local, active session (CoreCtrl's documented polkit
 rule; every other administrator action still asks), and CoreCtrl starts at
 login in the system tray, by its own setting, which stays the person's.
 While CoreCtrl or LACT holds the processor's governor or an AMD graphics
 card's power level, power-profiles-daemon and tuned are kept off that
 setting, and the person is told which program holds it.
CONTROL
(cd "$D" && find usr -type f -exec md5sum {} + | sort -k2) >"$D/DEBIAN/md5sums"
chmod 644 "$D/DEBIAN/control" "$D/DEBIAN/md5sums" "$D/DEBIAN/conffiles"
# the gate runs in a container that is given the host's facts; the source package is built again with dpkg-buildpackage
# (repo/rebuild-script-source.py), so check-debs writes the complete build record (ORDER 639)
TREE=$(cd "$HERE/../../.." && pwd)
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lean-standalone-$PKG" --ulimit core=1 --cpus "${CPUS:-4}" --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -e PYTHONPATH="$TREE/sparky-os" \
	-e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
	-v "$TREE":"$TREE":ro -v "$D":"$D" -v "$OUT":"$OUT" "$IMAGE" sh -c 'python3 -m lean.standalone "$1" "$2" --authoring "$3" --build-dependency sparky-stereo-problems && python3 "$PYTHONPATH/repo/rebuild-script-source.py" "$2/$4_$5.dsc" && cd "$2" && python3 -m lean.release check-debs ./*_all.deb' sh "$D" "$OUT" "$HERE" "$PKG" "$VERSION"
