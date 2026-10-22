#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-beep, Daniel's and Paweł's PC speaker notifier for the Server Edition
# (github.com/Sparky-OS/sparky-beep), the way SparkyLinux packages its own tools: the
# install.sh layout laid into a DEBIAN tree (control in deb-package-builder's field order,
# md5sums, copyright only under /usr/share/doc), dpkg-deb -b, root owner, and beside it
# the source stub of the repository's deb-src (3.0 (quilt): the git tree as .orig.tar.xz,
# debian/ as .debian.tar.xz). Units go to /usr/lib/systemd/system (Forky's merged /usr).
# Run it inside a debian:testing container with dpkg-dev (dpkg-deb, dpkg-source, xz).
# Last update 2026/10/15
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-${SPARKY_SOURCES:?}/sparky-beep}
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparky-beep
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$SRC/CHANGELOG")
[ -n "$VERSION" ] || { echo "no version in $SRC/CHANGELOG"; exit 1; }
VERSION=$VERSION+lc1
W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}/sparky-os}/beep-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
S=$D/usr/share/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$D/etc/init.d" "$D/etc/$PKG" "$D/usr/lib/systemd/system" \
	"$S/lib" "$S/locale" "$S/compositions" "$D/usr/share/doc/$PKG"

# the install.sh layout
install -m 755 "$SRC"/bin/sparky-beep-* "$D/usr/bin/"
# init.d/beep_example_composer is an example for the docs, not a service of the package
for f in "$SRC"/init.d/*; do
	case "$f" in *beep_example_composer) ;; *) install -m 755 "$f" "$D/etc/init.d/" ;; esac
done
install -m 644 "$SRC"/system/*.service "$D/usr/lib/systemd/system/"
install -m 644 "$SRC"/lib/*.sh "$S/lib/"
install -m 644 "$SRC"/locale/*.lang "$SRC"/locale/i18n.sh "$S/locale/"
install -m 644 "$SRC"/compositions/*.beepmusic "$S/compositions/"
install -m 644 "$SRC/config/beep.conf" "$D/etc/$PKG/beep.conf"
install -m 644 "$SRC/copyright" "$D/usr/share/doc/$PKG/copyright"
for s in preinst postinst prerm postrm; do
	[ -f "$SRC/debian/$s" ] && install -m 755 "$SRC/debian/$s" "$D/DEBIAN/$s"
done
echo "/etc/$PKG/beep.conf" >"$D/DEBIAN/conffiles"

SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOC
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: apt, bash, bc, beep, coreutils, grep, sed, systemd
Recommends: whiptail | dialog, yad | zenity
Suggests: netdata, openssh-server, samba, webmin
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Beep
  Provides beep support for a few services of server edition: the PC speaker
  plays a tune when ssh, samba, netdata or webmin start, stop or restart.
  With a musical composer (sparky-beep-compose), a player and configuration
  tools in text and graphical mode, in 26 languages.
EOC
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort |
	grep -v -x -F -f <(sed 's|^/||' DEBIAN/conffiles) | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT" "$W/authoring"
cp "$HERE/build.sh" "$W/authoring/build.sh"
cp -a "$SRC" "$W/authoring/source"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$W/authoring"
