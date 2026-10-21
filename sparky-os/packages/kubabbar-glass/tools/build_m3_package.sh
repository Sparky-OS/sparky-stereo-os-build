#!/bin/bash
# Build the milestone 3 package and stage it with SHA256SUMS. Run inside the fixture image (it has dpkg-deb), as the lane user.
#   sparky-stereo-look-kubabbar-glass-menubar   the menu bar and dock layout variant: Look and Feel with its layout, splash and strings,
#                                               the launcher logo, and kubabbar-glass-minimize (Magic Lamp or Squash)
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
dest=${DEST:-/K3D/temp/sparky-os/pending-pack/classic-look/m3}
version=${VERSION:-20261014.7~sparky9~1+lc1}
base=${BASE_VERSION:-20261014.6~sparky9~1+lc1}
work=$(mktemp -d "${TMPDIR:-/K3D/temp}/kubabbar-m3-pkg.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$dest"
if compgen -G "$dest/*.deb" >/dev/null; then
	echo "Use an empty candidate output directory; existing archives are retained." >&2
	exit 1
fi
credit='Sparky Stereo OS, an edition of SparkyLinux, created by Paweł "pavroo" Pijanowski <pavroo@onet.eu> and Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
p=sparky-stereo-look-kubabbar-glass-menubar
k=$work/$p
mkdir -p "$k/usr/share/plasma/look-and-feel" "$k/usr/share/icons/hicolor/scalable/apps" "$k/usr/bin" "$k/usr/share/sparky/kubabbar-glass-minimize" "$k/usr/share/doc/$p"
cp -a "$repo/share/plasma/look-and-feel/kubabbar-glass-menubar" "$k/usr/share/plasma/look-and-feel/"
install -m 644 "$repo/share/icons/hicolor/scalable/apps/kubabbar-glass-launcher.svg" "$k/usr/share/icons/hicolor/scalable/apps/"
install -m 755 "$repo/bin/kubabbar-glass-minimize" "$k/usr/bin/"
install -m 644 "$repo/lang/minimize/"* "$k/usr/share/sparky/kubabbar-glass-minimize/"
cat > "$k/usr/share/doc/$p/copyright" <<COPYRIGHT
Upstream Author(s):

    Daniel Ramos and EchoSystems AI studios

Files: *
    Copyright 2026 Daniel Ramos and EchoSystems AI studios
    License: GPL-3

The launcher logo and the splash are original drawings (an eight-pointed star, an ancient Mesopotamian sign, in a silver glass disc).
The layout (a menu bar on top and a dock) is an idea, not artwork.
The KDE Store was searched for a Mac OS 8 style splash and icon pack; none was clean (see the source archive, study/m3.md), so none is used.
No Apple artwork, font, logo or name is used.

$credit

This package is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the
Free Software Foundation; version 3 of the License.
On Debian systems, the complete text of the GNU General Public License version 3 can be found in /usr/share/common-licenses/GPL-3.
COPYRIGHT
cp "$repo/ABOUT.md" "$repo/README.md" "$k/usr/share/doc/$p/"
mkdir -p "$k/DEBIAN"
{
	echo "Package: $p"
	echo "Version: $version"
	echo "Architecture: all"
	echo "Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>"
	echo "Installed-Size: $(du -sk "$k" | cut -f1)"
	echo "Depends: sparky-stereo-look-kubabbar-glass (>= $base), plasma-workspace, plasma-desktop, kwin-wayland, libkf6config-bin, dbus-bin"
	# Earlier base packages accidentally included this optional variant's files.
	# Allow their ownership to move here in either unpack order.
	echo "Breaks: sparky-stereo-look-kubabbar-glass (<< 20261014.6~sparky9~1+lc1)"
	echo "Replaces: sparky-stereo-look-kubabbar-glass (<< 20261014.6~sparky9~1+lc1)"
	echo "Section: Themes"
	echo "Priority: optional"
	echo "Homepage: https://sparkylinux.org"
	echo "Description: Kubabbar Glass, menu bar and dock"
	echo " Kubabbar Glass is our own name for this look, chosen by Daniel Ramos on 14 October 2026."
	echo " A layout variant of Kubabbar Glass: the application menu (Plasma's Global Menu) in a bar at the top after our own launcher logo,"
	echo " a floating, centred dock at the bottom with the icons-only task manager, and Magic Lamp for minimised windows."
	echo " kubabbar-glass-minimize chooses Squash instead."
} > "$k/DEBIAN/control"
(cd "$k" && find . -type f ! -path './DEBIAN/*' -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' md5sum > DEBIAN/md5sums)
chmod -R go-w "$k"
PYTHONPATH="$repo/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$k" "$dest" --authoring "$repo"
(cd "$dest" && sha256sum ./*.deb | sed 's|\./||' > SHA256SUMS)
printf "%s\n" "${SOURCE_COMMIT:-unknown}" > "$dest/SOURCE-COMMIT"
cat "$dest/SHA256SUMS"
