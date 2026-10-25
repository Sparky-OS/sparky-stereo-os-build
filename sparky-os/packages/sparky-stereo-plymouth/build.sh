#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL2 License
# Last update 2026/10/16
#
# Builds sparky-stereo-plymouth: the sparky-stereo-lines boot splash themes, generated from
# sparky-lines (upstream/sparky-lines, read only) by gen-theme.py.
#   build.sh OUTDIR
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-.}")
VERSION=20261025~sparky9~0+lc1
PKG=sparky-stereo-plymouth
umask 022
mkdir -p "$OUT"
D=$(mktemp -d "${TMPDIR:-/tmp}/stereo-boot-build.XXXXXX")
trap 'rm -rf "$D"' EXIT
chmod 755 "$D"
T=$D/usr/share/plymouth/themes
mkdir -p "$T/sparky-stereo-lines" "$T/sparky-stereo-lines-height" "$D/usr/share/doc/$PKG" "$D/DEBIAN"
for f in background.png electron.png logo.png password_dot16.png password_dot.png \
	password_field16.png password_field.png; do
	install -m 644 "$HERE/upstream/sparky-lines/$f" "$T/sparky-stereo-lines/$f"
done
# the SparkyOS logo (Daniel's wordmark of 2026-10-07: SPARKYOS / POWERED BY DEBIAN / STEREO 3D EDITION), the same
# picture as sparkyos-plymouth's wordmark.png
install -m 644 "$HERE/art/wordmark.png" "$T/sparky-stereo-lines/wordmark.png"
# the edition's default boot splash, at the distribution level: Plymouth reads /etc/plymouth/plymouthd.conf (a chosen
# theme), then /usr/share/plymouth/plymouthd.defaults (the distribution's), then the default.plymouth alternative
# (src/main.c, show_default_splash); Plymouth's own defaults file is diverted to plymouthd.defaults.debian
install -D -m 644 "$HERE/plymouthd.defaults" "$D/usr/share/plymouth/plymouthd.defaults"
install -m 755 "$HERE/debian-scripts/preinst" "$HERE/debian-scripts/postinst" "$HERE/debian-scripts/prerm" "$HERE/debian-scripts/postrm" "$D/DEBIAN/"
printf 'interest-noawait /usr/share/plymouth/themes/sparky-blue\ninterest-noawait /usr/share/plymouth/themes/sparkyos-stereo\nactivate-noawait update-initramfs\n' > "$D/DEBIAN/triggers"
python3 "$HERE/gen-theme.py" "$HERE/upstream/sparky-lines/sparky-lines.script" "$T/sparky-stereo-lines/sparky-stereo-lines.script" slope
python3 "$HERE/gen-theme.py" "$HERE/upstream/sparky-lines/sparky-lines.script" "$T/sparky-stereo-lines-height/sparky-stereo-lines-height.script" height
theme() {
	cat > "$T/$1/$1.plymouth" <<THEME
[Plymouth Theme]
Name=$2
Description=$3
ModuleName=script
Stereo=full-side-by-side

[script]
ImageDir=/usr/share/plymouth/themes/sparky-stereo-lines
ScriptFile=/usr/share/plymouth/themes/$1/$1.script
THEME
}
theme sparky-stereo-lines "Sparky Stereo Lines" "The Sparky lines boot splash in stereo 3D: drawn once per eye from one animation clock, the electrons popping where the curves rise and sinking where they fall"
theme sparky-stereo-lines-height "Sparky Stereo Lines (height)" "The Sparky lines boot splash in stereo 3D, the electrons popping in the upper half of each curve and sinking in the lower half"
chmod 644 "$T"/*/*
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat > "$D/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: plymouth (>= 26.134.222-1+stereo3d1)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo OS boot splash themes in stereo 3D
  The sparky-stereo-lines themes: the Sparky lines boot splash drawn once
  per eye. On a stereo output (plymouth.stereo=, written by
  sparky-stereo-boot from the saved choice of the main screen) each eye
  gets its own picture, the electrons popping and sinking along their
  curves; on a 2D screen the theme draws once. Two depth rules:
  sparky-stereo-lines (the slope of the curve) and
  sparky-stereo-lines-height (the height on the curve). The background is on
  the screen, the swirl with its orbits one step in front, the SparkyOS logo
  one more step in front. sparky-stereo-lines is the edition's default boot
  splash; a theme chosen with plymouth-set-default-theme stays.
CONTROL
(cd "$D" && find usr -type f -exec md5sum {} + | sort -k2) > "$D/DEBIAN/md5sums"
chmod 644 "$D/DEBIAN/control" "$D/DEBIAN/md5sums" "$D/DEBIAN/triggers"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone \
    "$D" "$OUT" --authoring "$HERE"
