#!/bin/bash
# Build Kubabbar Glass 9's package and stage it with SHA256SUMS. Run inside the build image (it has dpkg-deb and the
# problems engine), as the lane user.
#   sparky-stereo-look-kubabbar-glass-9   the classic variant of Kubabbar Glass (queue row 147): its Look and Feel, colour
#                                         schemes, Kvantum themes, window decoration, Plasma style, wallpaper, the
#                                         fontconfig aliases for the classic font names, and the session helper
# The family's icons, cursors and loading screen come from sparky-stereo-look-kubabbar-glass, a dependency.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dest=${DEST:-${SPARKY_STAGING_DIR:?}/classic-look/glass9}
. "$repo/package-versions.sh"
version=${GLASS9_VERSION:?package-versions.sh must define GLASS9_VERSION}
kvantum=${KVANTUM_MIN_VERSION:?package-versions.sh must define KVANTUM_MIN_VERSION}
gtk9=${GTK9_MIN_VERSION:?package-versions.sh must define GTK9_MIN_VERSION}
menubar=${MENUBAR_MIN_VERSION:?package-versions.sh must define MENUBAR_MIN_VERSION}
work=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/kubabbar-glass9-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
RECIPE=$repo
COPY="$RECIPE/../../../tools/copy-recipe.py"
python3 "$COPY" "$RECIPE" "$work/authoring"
mkdir -p "$work/authoring/build-tools"
cp "$COPY" "$work/authoring/build-tools/"
repo=$work/authoring
mkdir -p "$dest"
if compgen -G "$dest/*.deb" >/dev/null; then
	echo "Use an empty candidate output directory; existing archives are retained." >&2
	exit 1
fi
credit="Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł \"pavroo\" Pijanowski)"
p=sparky-stereo-look-kubabbar-glass-9
k=$work/$p
s=$repo/share
mkdir -p "$k/usr/share/plasma/look-and-feel" "$k/usr/share/plasma/desktoptheme" "$k/usr/share/aurorae/themes" \
	"$k/usr/share/kwin/decorations" "$k/usr/share/color-schemes" "$k/usr/share/Kvantum" "$k/usr/share/wallpapers" \
	"$k/usr/share/fontconfig/conf.avail" "$k/etc/fonts/conf.d" "$k/usr/bin" "$k/usr/share/sparky/kubabbar-glass-9-scrolling" \
	"$k/usr/lib/systemd/user/graphical-session.target.wants" "$k/etc/xdg/autostart" "$k/usr/share/doc/$p"
cp -a "$s/plasma/look-and-feel/kubabbar-glass-9" "$s/plasma/look-and-feel/kubabbar-glass-9-menubar" "$k/usr/share/plasma/look-and-feel/"
mkdir -p "$k/usr/share/sddm/themes"
cp -a "$s/sddm/themes/kubabbar-glass-9" "$k/usr/share/sddm/themes/"
cp -a "$s/plasma/desktoptheme/kubabbar-glass-9" "$k/usr/share/plasma/desktoptheme/"
cp -a "$s/aurorae/themes/kubabbar-glass-9" "$k/usr/share/aurorae/themes/"
cp -a "$s/kwin/decorations/kubabbar-glass-9" "$k/usr/share/kwin/decorations/"
cp -a "$s/color-schemes/"kubabbar-glass-9*.colors "$k/usr/share/color-schemes/"
cp -a "$s/Kvantum/"KubabbarGlass9* "$k/usr/share/Kvantum/"
cp -a "$s/wallpapers/kubabbar-glass-9" "$k/usr/share/wallpapers/"
install -m 644 "$s/fontconfig/conf.avail/45-kubabbar-glass-9.conf" "$k/usr/share/fontconfig/conf.avail/"
ln -s ../../../usr/share/fontconfig/conf.avail/45-kubabbar-glass-9.conf "$k/etc/fonts/conf.d/45-kubabbar-glass-9.conf"
install -m 755 "$repo/bin/kubabbar-glass-9-sync" "$repo/bin/kubabbar-glass-9-scrolling" "$k/usr/bin/"
install -m 644 "$repo/lang/scrolling9/"* "$k/usr/share/sparky/kubabbar-glass-9-scrolling/"
install -m 644 "$repo/lib/systemd/user/kubabbar-glass-9-sync.service" "$repo/lib/systemd/user/kubabbar-glass-9-sync.path" "$k/usr/lib/systemd/user/"
ln -s ../kubabbar-glass-9-sync.path "$k/usr/lib/systemd/user/graphical-session.target.wants/kubabbar-glass-9-sync.path"
install -m 644 "$repo/etc/xdg/autostart/kubabbar-glass-9-sync.desktop" "$k/etc/xdg/autostart/"
# the helper's messages for sparky-stereo-problems, in the ten languages
sparky-stereo-problems catalog "$p" "$repo/lang/glass9" "$k/usr/lib/systemd/catalog" --subject LOCAL1
cat > "$k/usr/share/doc/$p/copyright" <<COPYRIGHT
Upstream Author(s):

    Daniel Ramos and EchoSystems AI studios

Files: *
    Copyright 2026 Daniel Ramos and EchoSystems AI studios
    License: GPL-3

Every drawing here is original: the Kvantum themes' controls, the window frame and its buttons, the Plasma style and the
wallpaper are drawn by the recipe's generators (tools/make_kvantum9.py, tools/draw_theme9.py) from rectangles, discs and
triangles. The look recalls the classic Mac OS 9 appearance (Apple, 1999 to 2001) as an inspiration only: no Apple
artwork, font, logo or name is used. It is inspired by the KDE themes Platinum (Niels van Mourik, kde-aurorae-platinum
and kde-look-and-feel-platinum) and QPlatinum (Zinjanthr0pus); none of their files is used.

The fonts: the look names the classic fonts Charcoal, Geneva and Monaco and uses them where the person has them
installed; it ships, bundles, converts and downloads none of them. Where they are missing, fontconfig gives the free
fonts measured nearest to them, credited from their own name tables: Noto Sans Display (Copyright 2015 Google Inc.,
designed by the Monotype Design Team, SIL Open Font License 1.1; fonts-noto-core), DejaVu Sans (Bitstream, Inc., with
glyphs by Tavmjong Bah, the DejaVu fonts team; the Bitstream Vera licence, the DejaVu changes in the public domain;
fonts-dejavu-core) and Inconsolata (The Inconsolata Project Authors, designed by Raph Levien, Cyreal and Brenton Simpson,
SIL Open Font License 1.1; fonts-inconsolata); they are dependencies, not copied.

The Kvantum themes need the scroll_arrows_together key of the edition's Kvantum (kvantum 1.1.8-1+stereo3d1, Tsu Jan's
Kvantum with one patch of ours).

The loading screen, the login screen (an SDDM theme) and the menu bar layout are made by tools/make_login9.py; the login
screen is modelled on the classic Multiple Users window (Mac OS 9.0, from Apple's own Mac OS 9 Help), drawn original.

Files: usr/share/plasma/look-and-feel/kubabbar-glass-9/contents/splash/images/background.png
    The boot splash's background without its logo (sparky-stereo-plymouth, sparky-stereo-lines/background.png):
    Copyright 2014 Juliette Taka Belin and Aurélien Couderc (Debian 8 "Jessie" lines theme)
    Copyright 2018-2020 Paweł "pavroo" Pijanowski and Daniel Ramos (sparky-lines, the Sparky black set)
    License: GPL-2+

The loading screen shows the Sparky logo from the edition's artwork package (/usr/share/pixmaps/sparkyos.png) where it
is installed; this package does not carry it.

$credit

This package is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the
Free Software Foundation; version 3 of the License.
On Debian systems, the complete text of the GNU General Public License version 3 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT
cp "$repo/ABOUT.md" "$repo/README.md" "$k/usr/share/doc/$p/"
mkdir -p "$k/DEBIAN"
cat > "$k/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if [ "$1" = remove ]; then
	sparky-stereo-problems clear --all sparky-stereo-look-kubabbar-glass-9
fi
POSTRM
chmod 755 "$k/DEBIAN/postrm"
echo /etc/xdg/autostart/kubabbar-glass-9-sync.desktop > "$k/DEBIAN/conffiles"
{
	echo "Package: $p"
	echo "Version: $version"
	echo "Architecture: all"
	echo "Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>"
	echo "Installed-Size: $(du -sk "$k" | cut -f1)"
	# the decoration's QML imports KSvg and KWin's decoration module; the helper uses kreadconfig6, kwriteconfig6,
	# dbus-send and fc-list; the fallback fonts are the measured ones; Kvantum must know scroll_arrows_together
	# its GTK themes are sparky-stereo-gtk's; the menu bar layout takes the family's launcher logo and adds Plasma's window
	# list (plasma-widgets-addons); the loading screen imports QtQuick.Effects, org.kde.coreaddons (KOSRelease) and
	# org.sparky.stereo (StereoDepth), the login screen QtQuick.Controls and org.sparky.stereo
	echo "Depends: sparky-stereo-look-kubabbar-glass (>= 20261014.6~sparky9~0), sparky-stereo-look-kubabbar-glass-menubar (>= $menubar), sparky-stereo-look, sparky-stereo-gtk (>= $gtk9), qt-style-kvantum (>= $kvantum), kwin-style-aurorae, qml6-module-org-kde-ksvg, qml6-module-qtquick, qml6-module-qtquick-effects, qml6-module-qtquick-controls, qml6-module-org-kde-coreaddons, libstereo-layer1 (>= 1.20.0), plasma-widgets-addons, libkf6config-bin, dbus-bin, fontconfig, fonts-noto-core, fonts-dejavu-core, fonts-inconsolata, sparky-stereo-problems"
	# the Sparky logo of the loading screen; SDDM, for the person who chooses it as the login manager
	echo "Recommends: sparkyos-artwork, sddm"
	echo "Section: Themes"
	echo "Priority: optional"
	echo "Homepage: https://sparkylinux.org"
	echo "Description: Kubabbar Glass 9, the classic controls of the Kubabbar family"
	echo " Kubabbar Glass 9 is a variant of Kubabbar Glass, our own name for this family of looks, chosen by Daniel Ramos on"
	echo " 14 October 2026. Every control is drawn in a classic bevelled form (the ringed default button, the gripped scroll"
	echo " box with both arrows together at the end of the scrollbar, striped progress bars, rounded tabs, disclosure"
	echo " triangles), in the family's glass. Accent variations are colour schemes; kubabbar-glass-9-scrolling puts the"
	echo " scroll arrows at both ends instead. The classic font names are used where installed and fall back to free fonts."
	echo " A menu bar layout (the application menu on a bar at the top, a window list at its right end, a dock), its own"
	echo " loading screen and an SDDM login screen in the classic style come with it; GTK programs follow through"
	echo " sparky-stereo-gtk."
} > "$k/DEBIAN/control"
(cd "$k" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' md5sum > DEBIAN/md5sums)
chmod -R go-w "$k"
PYTHONPATH="$RECIPE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$k" "$dest" --authoring "$repo" --build-dependency sparky-stereo-problems
# the source closure, as build_packages.sh makes it: the genuine .buildinfo and .changes from a rebuild of the retained
# source, then the gate that writes the build record (the provenance facts come from build-provenance.sh)
python3 "$RECIPE/../../repo/rebuild-script-source.py" "$dest/${p}_$version.dsc"
(cd "$dest" && PYTHONPATH="$RECIPE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release check-debs ./"$p"_"$version"_all.deb ./"$p"-lc-hr_"$version"_all.deb)
(cd "$dest" && sha256sum ./*.deb | sed 's|\./||' > SHA256SUMS)
printf "%s\n" "${SOURCE_COMMIT:-${SPARKY_BUILD_COMMIT:-unknown}}" > "$dest/SOURCE-COMMIT"
cat "$dest/SHA256SUMS"
