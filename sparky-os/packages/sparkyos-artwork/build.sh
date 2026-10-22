#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Builds sparkyos-artwork, the SparkyOS artwork of release 9 "Mashtabba", from the artwork repository's
# 9/ folder (ART), installed where its install.sh puts it, as sparky-artwork does for SparkyLinux:
# the swirl pixmaps, /opt/artwork (the Oxygen wallpaper flat and as a stereo pair, the GRUB background),
# the eighteen stereo wallpapers in /usr/share/wallpapers. Also the Oxygen wallpaper as a Plasma
# wallpaper package, SparkyOSOxygen (its pictures link to /opt/artwork), which the Sparky Stereo
# Oxygen Plasma style names as its default wallpaper. GRUB's background is the SparkyOS one
# (/etc/default/grub.d/20-sparkyos-artwork.cfg; a background the person chose is kept). Needs dpkg-deb and
# python3-pil.
# Last update 2026/10/16
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ART=${ART:-${SPARKY_SCRATCH:?}/sparky-os/artwork-repo/9}
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparkyos-artwork
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
VERSION=$VERSION+lc1
W=$(mktemp -d "${TMPDIR:-/tmp}/sparkyos-artwork.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/share/pixmaps" "$D/opt/artwork" "$D/usr/share/wallpapers" "$D/usr/share/doc/$PKG"
cp "$ART"/pixmaps/* "$D/usr/share/pixmaps/"
cp "$ART"/opt/sparkyos-oxygen.png "$ART"/opt/sparkyos-oxygen-3d.pns "$ART"/opt/sparkyos-grub.png "$D/opt/artwork/"
ln -s /opt/artwork/sparkyos-oxygen.png "$D/opt/artwork/sparkyos-desktop.png"
ln -s /opt/artwork/sparkyos-oxygen-3d.pns "$D/opt/artwork/sparkyos-desktop-3d.pns"
cp -r "$ART"/wallpapers/* "$D/usr/share/wallpapers/"
# the Oxygen wallpaper as a Plasma wallpaper package: the flat picture where Plasma looks, the pair where the
# stereo desktop looks, both linked to /opt/artwork; a small screenshot for the wallpaper chooser
O=$D/usr/share/wallpapers/SparkyOSOxygen
mkdir -p "$O/contents/images" "$O/contents/stereo"
ln -s /opt/artwork/sparkyos-oxygen.png "$O/contents/images/3840x2160.png"
ln -s /opt/artwork/sparkyos-oxygen-3d.pns "$O/contents/stereo/7680x2160.pns"
python3 -c "
from PIL import Image
im = Image.open('$ART/opt/sparkyos-oxygen.png').convert('RGB'); im.thumbnail((400, 225)); im.save('$O/contents/screenshot.png')"
cat >"$O/metadata.json" <<'EOS'
{
    "KPlugin": {
        "Authors": [
            {
                "Name": "Daniel Ramos (Capitain Jack)"
            }
        ],
        "Id": "SparkyOSOxygen",
        "License": "GPL-2.0-or-later",
        "Name": "SparkyOS Oxygen (3D)"
    }
}
EOS
install -D -m 644 "$HERE/grub-background.cfg" "$D/etc/default/grub.d/20-sparkyos-artwork.cfg"
cp "$ART/copyright" "$D/usr/share/doc/$PKG/copyright"
cat >>"$D/usr/share/doc/$PKG/copyright" <<'EOS'

Files: usr/share/wallpapers/SparkyOSOxygen/*
    The Oxygen wallpaper above (opt/sparkyos-oxygen.png and its pair), as a Plasma wallpaper package
    made by this package's build; its screenshot is the picture scaled down.
    Copyright 2019-2026 (C) Daniel Ramos (Capitain Jack)
    License: GPL-2+
EOS
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
# the system's default background, as sparky-artwork links its own when none is there
if [ ! -d /usr/share/backgrounds ]; then
	mkdir -p /usr/share/backgrounds
fi
if [ ! -e /usr/share/backgrounds/default.png ]; then
	ln -s /opt/artwork/sparkyos-oxygen.png /usr/share/backgrounds/default.png
fi
# GRUB's background (/etc/default/grub.d/20-sparkyos-artwork.cfg) on a system that boots with GRUB
if [ "$1" = configure ] && [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then
	update-grub || true
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	if [ "$(readlink /usr/share/backgrounds/default.png 2>/dev/null)" = "/opt/artwork/sparkyos-oxygen.png" ]; then
		rm -f /usr/share/backgrounds/default.png
	fi
fi
if [ "$1" = "purge" ] && [ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ]; then
	update-grub || true
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
find "$D" -path "$D/DEBIAN" -prune -o -type d -exec chmod 755 {} + ; find "$D" -path "$D/DEBIAN" -prune -o -type f -exec chmod 644 {} +
echo /etc/default/grub.d/20-sparkyos-artwork.cfg >"$D/DEBIAN/conffiles"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: SparkyOS Artwork
  Backgrounds for the Sparky Stereo OS desktop, GRUB and other system
  elements: the SparkyOS Oxygen wallpaper, flat and as a stereo pair, the
  GRUB background, the swirl pixmaps and eighteen stereo wallpapers for
  Plasma, each with its flat picture and its full side by side pair.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
mkdir -p "$W/authoring"
cp -a "$HERE/." "$W/authoring/"
cp -a "$ART" "$W/authoring/artwork"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$W/authoring"
