#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# gtk-proof.sh OUT: inside the rig image, as the person, from the installed packages: Kubabbar Glass 9 applied by Plasma's
# own plasma-apply-lookandfeel, its helper and sparky-stereo-gtk-sync run as at login; then the GTK 2, 3 and 4 galleries
# in the theme the sync chose, the arrow check (gtk-arrows.py) and Qt 6's gallery beside them; then the person's choice
# "apart" made with kubabbar-glass-9-scrolling and everything again. A control: GTK 3 in Breeze, where the check must
# fail. One line per row in OUT/rows.txt (PASS or FAIL); exit 1 when a row that must pass fails.
# Env: GTK2_GALLERY (a gallery-gtk2 built for the image).
set -u
OUT=$1
M9=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
home=$(mktemp -d)
export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_RUNTIME_DIR=$home/run XDG_CONFIG_DIRS=$home/.config/kdedefaults:/etc/xdg \
	XDG_CURRENT_DESKTOP=KDE KDE_SESSION_VERSION=6 LANG=C.UTF-8
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"; chmod 700 "$XDG_RUNTIME_DIR"
assets=/usr/share/themes/Kubabbar-Glass-9/assets
rows=$OUT/rows.txt; : > "$rows"
bad=0
row() { echo "$1 $2" >> "$rows"; echo "$1 $2"; [ "$1" = PASS ] || bad=1; }

dbus-run-session -- bash -c "
	QT_QPA_PLATFORM=offscreen plasma-apply-lookandfeel -a kubabbar-glass-9 > '$OUT/apply.txt' 2>&1
	kubabbar-glass-9-sync >> '$OUT/apply.txt' 2>&1
	sparky-stereo-gtk-sync >> '$OUT/apply.txt' 2>&1
	echo exit \$? >> '$OUT/apply.txt'
"
for arrows in together apart; do
	if [ "$arrows" = apart ]; then
		dbus-run-session -- kubabbar-glass-9-scrolling apart > "$OUT/scrolling-apart.txt" 2>&1
		echo "exit $?" >> "$OUT/scrolling-apart.txt"
	fi
	theme=$(sed -n 's/^gtk-theme-name=//p' "$XDG_CONFIG_HOME/gtk-3.0/settings.ini")
	want=Kubabbar-Glass-9; [ "$arrows" = apart ] && want=Kubabbar-Glass-9-Apart
	[ "$theme" = "$want" ] && row PASS "sync-$arrows: sparky-stereo-gtk-sync chose $theme" || row FAIL "sync-$arrows: sparky-stereo-gtk-sync chose '$theme', expected $want"
	for kit in gtk2 gtk3 gtk4; do
		bash "$M9/gtk-gallery.sh" "$kit" session "$OUT/$arrows-$kit" > "$OUT/$arrows-$kit-driver.txt" 2>&1
		# GTK 4 too since the edition's gtk4 +stereo3d4 (row 147, milestone 3): its scrollbars have steppers a theme turns on
		expect=$arrows
		reported=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("theme"))' "$OUT/$arrows-$kit.json" 2>/dev/null)
		if python3 "$M9/gtk-arrows.py" "$OUT/$arrows-$kit-window.png" "$OUT/$arrows-$kit.json" "$assets" "$expect" > "$OUT/$arrows-$kit-arrows.txt" 2>&1 \
			&& [ "$reported" = "$want" ]; then
			row PASS "$kit-$arrows: $kit loaded $reported; grips found; arrows $expect"
		else
			row FAIL "$kit-$arrows: $kit loaded '$reported'; $(tr '\n' ' ' < "$OUT/$arrows-$kit-arrows.txt")"
		fi
	done
	QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=kde python3 "$M9/gallery.py" "$OUT/$arrows-qt6.png" > "$OUT/$arrows-qt6.txt" 2>&1
	grep -q -i kvantum "$OUT/$arrows-qt6.txt" && row PASS "qt6-$arrows: $(head -1 "$OUT/$arrows-qt6.txt")" || row FAIL "qt6-$arrows: $(head -1 "$OUT/$arrows-qt6.txt")"
done
# the control: Breeze draws none of the 9's pictures, so the same check fails
bash "$M9/gtk-gallery.sh" gtk3 Breeze "$OUT/control-gtk3" > "$OUT/control-gtk3-driver.txt" 2>&1
if python3 "$M9/gtk-arrows.py" "$OUT/control-gtk3-window.png" "$OUT/control-gtk3.json" "$assets" together > "$OUT/control-gtk3-arrows.txt" 2>&1; then
	row FAIL "control-gtk3-breeze: the check passed on Breeze, so it cannot fail"
else
	row PASS "control-gtk3-breeze: the check fails on Breeze (red, as it must)"
fi
python3 "$M9/gtk-sheet.py" "$OUT" > "$OUT/sheet.txt" 2>&1 || echo "sheet failed" >> "$OUT/sheet.txt"
rm -rf "$home"
exit $bad
