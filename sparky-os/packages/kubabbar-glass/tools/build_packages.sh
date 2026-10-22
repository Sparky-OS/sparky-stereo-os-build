#!/bin/bash
# Build the two milestone 2 packages and stage them with SHA256SUMS. Run inside the fixture image (it has dpkg-deb), as the lane user.
#   sparky-stereo-gtk                      GTK 3 and 4 themes for both looks and the script that picks the theme from the KDE colour scheme
#   sparky-stereo-look-kubabbar-glass      the classic look: Look and Feel, colours, window decoration, Plasma style, application style
#                                          options, cursors, splash, SDDM theme, 3D icon pilot, wallpaper
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dest=${DEST:-${SPARKY_STAGING_DIR:?}/classic-look/m2}
version=${VERSION:-20261014.6~sparky9~0+lc1}
look_version=${LOOK_VERSION:-20261014.6~sparky9~1+lc1}
work=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/kubabbar-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$dest"
if compgen -G "$dest/*.deb" >/dev/null; then
	echo "Use an empty candidate output directory; existing archives are retained." >&2
	exit 1
fi
credit='Sparky Stereo OS, an edition of SparkyLinux, created by Paweł "pavroo" Pijanowski <pavroo@onet.eu> and Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'

control() { # dir package depends recommends suggests description-lines...
	local d=$1 p=$2 dep=$3 rec=$4 sug=$5; shift 5
	mkdir -p "$d/DEBIAN"
	{
		echo "Package: $p"
		if [ "$p" = sparky-stereo-look-kubabbar-glass ]; then
			echo "Version: $look_version"
		else
			echo "Version: $version"
		fi
		echo "Architecture: all"
		echo "Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>"
		echo "Installed-Size: $(du -sk "$d" | cut -f1)"
		[ -n "$dep" ] && echo "Depends: $dep"
		[ -n "$rec" ] && echo "Recommends: $rec"
		[ -n "$sug" ] && echo "Suggests: $sug"
		echo "Section: Themes"
		echo "Priority: optional"
		echo "Homepage: https://sparkylinux.org"
		echo "Description: $1"
		shift
		for l in "$@"; do echo " $l"; done
	} > "$d/DEBIAN/control"
	(cd "$d" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' md5sum > DEBIAN/md5sums)
}
build() { # dir package
	find "$1" -name '*.qmlc' -delete
	chmod -R go-w "$1"
	PYTHONPATH="$repo/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$1" "$dest" --authoring "$repo"
}
doc() { # dir package copyright-body-file
	mkdir -p "$1/usr/share/doc/$2"
	cp "$3" "$1/usr/share/doc/$2/copyright"
}

# 1. sparky-stereo-gtk
g=$work/sparky-stereo-gtk
mkdir -p "$g/usr/bin" "$g/usr/share/themes" "$g/usr/lib/systemd/user/graphical-session.target.wants" "$g/etc/xdg/autostart"
install -m 755 "$repo/bin/sparky-stereo-gtk-sync" "$g/usr/bin/"
cp -a "$repo/share/themes/." "$g/usr/share/themes/"
install -m 644 "$repo/lib/systemd/user/"* "$g/usr/lib/systemd/user/"
ln -s ../sparky-stereo-gtk-sync.path "$g/usr/lib/systemd/user/graphical-session.target.wants/sparky-stereo-gtk-sync.path"
install -m 644 "$repo/etc/xdg/autostart/sparky-stereo-gtk-sync.desktop" "$g/etc/xdg/autostart/"
cat > "$work/gtk-copyright" <<COPYRIGHT
Upstream Author(s):

    Daniel Ramos and EchoSystems AI studios

Files: *
    Copyright 2026 Daniel Ramos and EchoSystems AI studios
    License: GPL-3

The GTK themes import the Breeze GTK shapes from the breeze-gtk-theme package (The KDE Developers, LGPL-2.1+, a dependency, not copied);
colors.css is generated from the KDE colour scheme by tools/kde2gtk_colors.py in the source archive.

$credit

This package is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the
Free Software Foundation; version 3 of the License.
On Debian systems, the complete text of the GNU General Public License version 3 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT
doc "$g" sparky-stereo-gtk "$work/gtk-copyright"
control "$g" sparky-stereo-gtk "breeze-gtk-theme, kde-config-gtk-style, libglib2.0-bin, libkf6config-bin" "" "" \
	"GTK 3 and GTK 4 themes that follow the Sparky Stereo OS looks" \
	"Kubabbar-Glass and Sparky-Stereo-Oxygen: the Breeze GTK shapes in each look's colours." \
	"sparky-stereo-gtk-sync picks the theme from the KDE colour scheme at login and whenever kdeglobals changes;" \
	"kde-config-gtk-style keeps the colours in step."
build "$g" sparky-stereo-gtk

# 2. sparky-stereo-look-kubabbar-glass
k=$work/sparky-stereo-look-kubabbar-glass
mkdir -p "$k/usr/share" "$k/usr/bin" "$k/usr/share/sparky/kubabbar-glass-style"
# The optional menubar package owns its layout and launcher. Copying all of share/
# also picked up milestone 3's files and made the two packages conflict on upgrade.
(cd "$repo/share" && tar cf - --exclude='./plasma/desktoptheme/sparky-stereo-oxygen' --exclude='./themes' \
	--exclude='./plasma/look-and-feel/kubabbar-glass-menubar' \
	--exclude='./icons/hicolor/scalable/apps/kubabbar-glass-launcher.svg' .) | tar xf - -C "$k/usr/share"
install -m 755 "$repo/bin/kubabbar-glass-style" "$k/usr/bin/"
for language in "$repo/lang/"*; do
	[ -f "$language" ] || continue
	install -m 644 "$language" "$k/usr/share/sparky/kubabbar-glass-style/"
done
cp "$repo/README.md" "$repo/ABOUT.md" "$work/" 2>/dev/null || true
cat > "$work/look-copyright" <<COPYRIGHT
Upstream Author(s):

    Daniel Ramos and EchoSystems AI studios

Files: *
    Copyright 2026 Daniel Ramos and EchoSystems AI studios
    License: GPL-3

Files: usr/share/Kvantum/KubabbarGlass/*
    Derived from KvGnome, Copyright Tsu Jan (Kvantum themes), GPL-3.0+; recoloured by Daniel Ramos and EchoSystems AI studios.
    License: GPL-3

The look is inspired by the KDE themes Platinum (Niels van Mourik, kde-aurorae-platinum and kde-look-and-feel-platinum) and QPlatinum
(Zinjanthr0pus, pling.com/u/zinjanthr0pus); none of their files is used, the artwork here is original.
Mac OS 8 (Apple, 1997) is an inspiration only; no Apple artwork, font, logo or name is used.

$credit

This package is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the
Free Software Foundation; version 3 of the License.
On Debian systems, the complete text of the GNU General Public License version 3 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT
doc "$k" sparky-stereo-look-kubabbar-glass "$work/look-copyright"
cp "$repo/README.md" "$repo/ABOUT.md" "$k/usr/share/doc/sparky-stereo-look-kubabbar-glass/"
control "$k" sparky-stereo-look-kubabbar-glass "kde-style-breeze, kwin-style-aurorae, libkf6config-bin, oxygen-icon-theme, sparky-stereo-gtk (= $version), sparky-stereo-look" \
	"kde-style-oxygen-qt6, qt6-style-kvantum, qt5-style-kvantum, sddm" "" \
	"Kubabbar Glass, the classic Sparky Stereo OS look" \
	"Kubabbar Glass is our own name for this look, chosen by Daniel Ramos on 14 October 2026." \
	"Look and Feel, colours, window decoration, Plasma style, cursors, splash, SDDM theme and the 3D icon pilot (the Trash)." \
	"The application style is Breeze by default; kubabbar-glass-style chooses Fusion, Kvantum or Oxygen instead."
build "$k" sparky-stereo-look-kubabbar-glass

(cd "$dest" && sha256sum ./*.deb | sed 's|\./||' > SHA256SUMS)
printf "%s\n" "${SOURCE_COMMIT:-unknown}" > "$dest/SOURCE-COMMIT"
cat "$dest/SHA256SUMS"
