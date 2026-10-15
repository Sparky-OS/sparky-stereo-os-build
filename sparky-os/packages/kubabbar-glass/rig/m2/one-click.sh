#!/bin/bash
# One-click apply, end to end, in a scratch home: install the Look and Feel package, apply it over an Oxygen configuration,
# then read back what a person's settings would hold. Run inside the fixture image.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
home=$root/rig/home/one-click
rm -rf "$home"
mkdir -p "$home/.config" "$home/.local/share/plasma/look-and-feel" "$home/runtime"
chmod 700 "$home/runtime"
export LANG=C.UTF-8 LC_ALL=C.UTF-8 HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share XDG_RUNTIME_DIR=$home/runtime QT_QPA_PLATFORM=offscreen
export XDG_DATA_DIRS=$root/share:/usr/local/share:/usr/share
cat > "$home/.config/kdeglobals" <<'CFG'
[KDE]
widgetStyle=oxygen

[General]
ColorScheme=OxygenDark

[Icons]
Theme=oxygen
CFG
printf '[Mouse]\ncursorTheme=Oxygen_Black\n' > "$home/.config/kcminputrc"
printf '[org.kde.kdecoration2]\nlibrary=org.kde.oxygen\n' > "$home/.config/kwinrc"
printf '[Theme]\nname=sparky-stereo-oxygen\n' > "$home/.config/plasmarc"
echo "== before"; kreadconfig6 --file kdeglobals --group KDE --key widgetStyle; kreadconfig6 --file kdeglobals --group General --key ColorScheme
kpackagetool6 -t Plasma/LookAndFeel -i "$root/share/plasma/look-and-feel/kubabbar-glass"
dbus-run-session -- sh -c '
	plasma-apply-lookandfeel -a kubabbar-glass
	echo "== apply exit $?"
'
echo "== after (read the way a Plasma session does: kdedefaults first in XDG_CONFIG_DIRS, as startplasma sets it)"
export XDG_CONFIG_DIRS=$home/.config/kdedefaults:/etc/xdg
for entry in "kdeglobals KDE widgetStyle" "kdeglobals General ColorScheme" "kdeglobals Icons Theme" "plasmarc Theme name" "kcminputrc Mouse cursorTheme" \
	"kwinrc org.kde.kdecoration2 library" "kwinrc org.kde.kdecoration2 theme" "kwinrc org.kde.kdecoration2 ButtonsOnLeft" "kwinrc org.kde.kdecoration2 ButtonsOnRight" \
	"kwinrc Effect-translucency Inactive" "kwinrc Effect-translucency Dialogs" "kwinrc Plugins blurEnabled" "ksplashrc KSplash Theme" "ksplashrc KSplash Engine"; do
	set -- $entry
	printf '%s [%s] %s = %s\n' "$1" "$2" "$3" "$(kreadconfig6 --file "$1" --group "$2" --key "$3")"
done
echo "== GTK sync (what the user path unit runs)"
PATH=$root/bin:$PATH sparky-stereo-gtk-sync
grep -h "gtk-theme-name\|prefer-dark" "$home/.config/gtk-3.0/settings.ini" "$home/.config/gtk-4.0/settings.ini"
