#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# gallery-compare.sh OUT: inside the rig image, as the person: for Kubabbar Glass 9 and Kubabbar Glass, a fresh home, the
# Look and Feel applied by Plasma's own plasma-apply-lookandfeel, the 9's session helper run as at login, then the
# gallery (rig/m9/gallery.py) offscreen: Qt 6 through KDE's platform theme (the style and palette the look applies);
# Qt 5 with the look's style named, because this image has no Qt 5 platform theme of KDE's (Debian removed
# plasma5-integration; the edition's carry is row 59's) and the scheme's palette given to it.
set -euo pipefail
OUT=$1
M9=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
for look in kubabbar-glass-9 kubabbar-glass; do
	home=$(mktemp -d)
	export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_RUNTIME_DIR=$home/run XDG_CONFIG_DIRS=$home/.config/kdedefaults:/etc/xdg
	mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"; chmod 700 "$XDG_RUNTIME_DIR"
	QT_QPA_PLATFORM=offscreen dbus-run-session -- plasma-apply-lookandfeel -a "$look" > "$OUT/$look-apply.txt" 2>&1
	# the session helper, as the autostart runs it at login (it acts only for the 9)
	kubabbar-glass-9-sync >> "$OUT/$look-apply.txt" 2>&1 || echo "sync exit $?" >> "$OUT/$look-apply.txt"
	cp -r "$XDG_CONFIG_HOME/kdedefaults" "$OUT/$look-kdedefaults"
	scheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)
	QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=kde XDG_CURRENT_DESKTOP=KDE \
		python3 "$M9/gallery.py" "$OUT/$look-qt6.png" > "$OUT/$look-qt6.txt" 2>&1
	style5=$(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle)
	QT_QPA_PLATFORM=offscreen QT_STYLE_OVERRIDE=$style5 \
		python3 "$M9/gallery.py" "$OUT/$look-qt5.png" --qt5 --palette "/usr/share/color-schemes/$scheme.colors" > "$OUT/$look-qt5.txt" 2>&1
	echo "$look scheme=$scheme style=$style5" >> "$OUT/summary.txt"
	rm -rf "$home"
done
