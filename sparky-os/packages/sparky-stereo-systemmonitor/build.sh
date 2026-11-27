#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
#
# Builds sparky-stereo-systemmonitor (hand assembled, Paweł's formula): System Monitor's Overview presets fitted to
# the computer by a hardware probe (queue row 182).
#   build.sh OUTDIR
# SPARKY_BUILD_IMAGE names the build image: Debian testing with dpkg-dev, gcc, node-acorn, nodejs, perl, python3,
# python3-yaml and sparky-stereo-problems (its catalog verb makes the journal catalogues).
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
PKG=sparky-stereo-systemmonitor
VERSION=0.1.0+lc1
IMAGE=${SPARKY_BUILD_IMAGE:?set SPARKY_BUILD_IMAGE to the build image (see the header)}
# the host's facts for the build record, and the source date from the recipe's last commit (ORDER 394b, ORDER 421b)
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$IMAGE" "$HERE"
umask 022
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.systemmonitor.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PKG"
# the probe and composer, run by the person's session at login (XDG autostart), only where System Monitor is installed
# (TryExec, Desktop Application Autostart Specification 0.5, 2.2)
install -D -m 755 "$HERE/bin/overview-pages" "$D/usr/libexec/$PKG/overview-pages"
install -D -m 644 "$HERE/share/sparky-stereo-systemmonitor-pages.desktop" "$D/etc/xdg/autostart/sparky-stereo-systemmonitor-pages.desktop"
# the pages' words in the ten languages, written into each page as Title[LANG] (KConfig's localized entries)
for lang in "$HERE"/lang/*; do
	install -D -m 644 "$lang" "$D/usr/share/$PKG/lang/$(basename "$lang")"
done
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
# the problem's sentences in the ten languages, as journal catalogues for the edition's one engine
# (the engine runs in a container: it is a package program)
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}catalog-$PKG" --ulimit core=1 --cpus "${CPUS:-4}" --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" -e HOME=/tmp -v "$HERE/problems-lang":/lang:ro -v "$D":"$D" "$IMAGE" \
	sparky-stereo-problems catalog "$PKG" /lang "$D/usr/lib/systemd/catalog" --subject LOCAL1
printf '%s\n' /etc/xdg/autostart/sparky-stereo-systemmonitor-pages.desktop >"$D/DEBIAN/conffiles"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: python3, libkf6config-bin, sparky-stereo-problems (>= 0.2.4)
Enhances: plasma-systemmonitor
Section: kde
Priority: optional
Homepage: https://sparkylinux.org
Description: System Monitor's Overview fitted to the computer it runs on
 At a person's first login, the graphics cards and processor threads of
 the computer are read, as System Monitor's own sensor service reads them,
 and four Overview presets are written for it (one graphics card or every
 one, few or many processor threads). The one that fits the computer
 becomes the page System Monitor opens with, also from Ctrl+Alt+Del; KDE's
 Overview and the other presets stay one choice away in Edit Pages, and
 the person's own choice afterwards is kept. Each card shows its usage,
 video memory, temperature and power where its driver reports them; what a
 driver does not report is named on the page, never shown as zero.
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
