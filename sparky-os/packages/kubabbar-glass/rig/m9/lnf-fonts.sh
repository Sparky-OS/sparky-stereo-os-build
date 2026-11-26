#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# lnf-fonts.sh OUT: inside the rig image, as the person, whose kdeglobals holds fonts of their own.
#   red    a test Look and Feel that carries fonts, applied by plasma-apply-lookandfeel: Plasma's manager writes them to
#          kdedefaults and removes the person's own values (KLookAndFeelManager::writeNewDefaults, revertToDefault);
#          the fonts are written in [kdeglobals][General] and [kdeglobals][WM] alike, so Plasma 6.7.4's swapped font
#          detection (fixed upstream in 0bf662de) still sees them
#   green  Kubabbar Glass 9, applied the same way, with its session helper: the person's own font lines stay as they
#          were (applying a look still writes its colour groups into the person's file, as every look does), and the
#          look's fonts are the defaults under them
# The person's file is read line by line: kreadconfig6 would give the cascaded default where a line is gone.
# Writes OUT/results.json; exits 1 when a row is not as expected.
set -uo pipefail
OUT=$1
mkdir -p "$OUT"
own='[General]
font=Charcoal,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
menuFont=Virtue,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1
fixed=Terminus,10,-1,5,700,0,0,0,0,0,0,0,0,0,0,1
'
case_home() {
	home=$(mktemp -d)
	export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share XDG_RUNTIME_DIR=$home/run
	export XDG_CONFIG_DIRS=$home/.config/kdedefaults:/etc/xdg
	mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME"; chmod 700 "$XDG_RUNTIME_DIR"
	printf '%s' "$own" > "$XDG_CONFIG_HOME/kdeglobals"
}
apply() { QT_QPA_PLATFORM=offscreen dbus-run-session -- plasma-apply-lookandfeel -a "$1" >> "$OUT/$2-apply.txt" 2>&1; }

# red
case_home
lnf=$XDG_DATA_HOME/plasma/look-and-feel/test-fonts-in-lnf
mkdir -p "$lnf/contents"
printf '{"KPlugin": {"Id": "test-fonts-in-lnf", "Name": "Fonts in a Look and Feel"}, "KPackageStructure": "Plasma/LookAndFeel"}\n' > "$lnf/metadata.json"
printf '[kdeglobals][General]\nfont=Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nmenuFont=Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n[kdeglobals][WM]\nfont=Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nmenuFont=Noto Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n' > "$lnf/contents/defaults"
apply test-fonts-in-lnf red
red_font=$(grep '^font=' "$XDG_CONFIG_HOME/kdeglobals" || true)
red_menu=$(grep '^menuFont=' "$XDG_CONFIG_HOME/kdeglobals" || true)
red_seen=$(kreadconfig6 --file kdeglobals --group General --key menuFont)
cp "$XDG_CONFIG_HOME/kdeglobals" "$OUT/red-kdeglobals-after"
rm -rf "$home"

# green
case_home
before=$(grep -E '^(font|menuFont|fixed|smallestReadableFont|toolBarFont|activeFont)=' "$XDG_CONFIG_HOME/kdeglobals" | sort | sha256sum | cut -d' ' -f1)
apply kubabbar-glass-9 green
kubabbar-glass-9-sync >> "$OUT/green-apply.txt" 2>&1
after=$(grep -E '^(font|menuFont|fixed|smallestReadableFont|toolBarFont|activeFont)=' "$XDG_CONFIG_HOME/kdeglobals" | sort | sha256sum | cut -d' ' -f1)
green_seen=$(kreadconfig6 --file kdeglobals --group General --key menuFont)
green_default=$(kreadconfig6 --file "$XDG_CONFIG_HOME/kdedefaults/kdeglobals" --group General --key menuFont)
green_style=$(kreadconfig6 --file kdeglobals --group KDE --key widgetStyle)
cp "$XDG_CONFIG_HOME/kdeglobals" "$OUT/green-kdeglobals-after"
cp -r "$XDG_CONFIG_HOME/kdedefaults" "$OUT/green-kdedefaults"
rm -rf "$home"

python3 - "$OUT" "$red_font" "$red_menu" "$red_seen" "$before" "$after" "$green_seen" "$green_default" "$green_style" <<'PY'
import json, sys
out, red_font, red_menu, red_seen, before, after, green_seen, green_default, green_style = sys.argv[1:]
rows = [
 {"row": "red: a Look and Feel that carries fonts removes the person's own font lines", "pass": red_font == "" and red_menu == "" and not red_seen.startswith("Virtue"),
  "own_font_after": red_font, "own_menuFont_after": red_menu, "menuFont_the_session_sees": red_seen},
 {"row": "green: Kubabbar Glass 9 leaves every font line of the person's kdeglobals as it was", "pass": before == after, "before": before, "after": after},
 {"row": "green: the person's own menu font is what the session sees", "pass": green_seen.startswith("Virtue,9,"), "seen": green_seen},
 {"row": "green: the look's font is the default under it", "pass": green_default.split(",")[0] in ("Charcoal", "Noto Sans Display"), "default": green_default},
 {"row": "green: the look's style applied", "pass": green_style == "kvantum", "widgetStyle": green_style},
]
json.dump(rows, open(f"{out}/results.json", "w"), indent=1)
for r in rows:
    print("PASS" if r["pass"] else "FAIL", r["row"])
sys.exit(0 if all(r["pass"] for r in rows) else 1)
PY
