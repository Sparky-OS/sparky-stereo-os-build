#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# gtk-gallery.sh TOOLKIT THEME OUT: one GTK gallery (gtk2, gtk3 or gtk4) in a fresh X server (Xvfb, no window manager),
# the theme named the way each toolkit reads it (GTK 2: a gtkrc naming it, as KDE's GTK settings write ~/.gtkrc-2.0;
# GTK 3 and 4: settings.ini, as sparky-stereo-gtk-sync writes it); three captures of the screen with real input:
# OUT-window.png (the window), OUT-menu.png (the File menu opened by a click), OUT-tip.png (the OK button's tool tip
# after the pointer rests on it); OUT.json the gallery's own report (the theme GTK loaded, where it drew).
set -euo pipefail
kit=$1 theme=$2 out=$3
M9=$(cd "$(dirname "$0")" && pwd)
home=$(mktemp -d)
trap 'kill "${app:-}" "${xvfb:-}" 2>/dev/null || true; rm -rf "$home"' EXIT
export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_RUNTIME_DIR=$home/run NO_AT_BRIDGE=1 GDK_BACKEND=x11
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME/gtk-3.0" "$XDG_CONFIG_HOME/gtk-4.0"
chmod 700 "$XDG_RUNTIME_DIR"
printf '[Settings]\ngtk-theme-name=%s\ngtk-overlay-scrolling=%s\n' "$theme" "${OVERLAY:-false}" | tee "$XDG_CONFIG_HOME/gtk-3.0/settings.ini" > "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
printf 'gtk-theme-name="%s"\n' "$theme" > "$home/.gtkrc-2.0"
export GTK2_RC_FILES=$home/.gtkrc-2.0
display=:$(( 50 + RANDOM % 400 ))
Xvfb "$display" -screen 0 1100x760x24 -nolisten tcp > "$out-xvfb.log" 2>&1 &
xvfb=$!
export DISPLAY=$display
for _ in $(seq 50); do xdpyinfo > /dev/null 2>&1 && break; sleep 0.1; done
case $kit in
	gtk2) "${GTK2_GALLERY:?}" "$out.json" > "$out-app.log" 2>&1 & ;;
	gtk3) python3 "$M9/gallery_gtk3.py" "$out.json" > "$out-app.log" 2>&1 & ;;
	gtk4) GSK_RENDERER=cairo python3 "$M9/gallery_gtk4.py" "$out.json" > "$out-app.log" 2>&1 & ;;
esac
app=$!
for _ in $(seq 100); do [ -s "$out.json" ] && break; sleep 0.1; done
[ -s "$out.json" ] || { echo "no report from the $kit gallery" >&2; cat "$out-app.log" >&2; exit 1; }
read -r fx fy ox oy w h < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(*d["file"], *d["ok"], *d["size"])' "$out.json")
# a loaded machine may map the window before it is drawn: wait until the capture shows it (not all one colour)
drawn() { python3 -c 'import sys; from PIL import Image; im=Image.open(sys.argv[1]).convert("L").crop((0,0,int(sys.argv[2]),int(sys.argv[3]))); lo,hi=im.getextrema(); sys.exit(0 if hi-lo>60 else 1)' "$@"; }
for _ in $(seq 20); do sleep 0.5; import -window root "$out-window.png"; drawn "$out-window.png" "$w" "$h" && break; done
# the File menu, opened by a click; the capture is taken again until the menu shows below the bar
for _ in $(seq 5); do
	xdotool mousemove "$fx" "$fy" click 1
	sleep 1
	import -window root "$out-menu.png"
	python3 -c 'import sys; from PIL import Image, ImageChops; a=Image.open(sys.argv[1]).convert("L").crop((0,30,200,90)); b=Image.open(sys.argv[2]).convert("L").crop((0,30,200,90)); sys.exit(0 if ImageChops.difference(a,b).getbbox() else 1)' "$out-window.png" "$out-menu.png" && break
	xdotool key Escape; sleep 0.5
done
xdotool key Escape
sleep 0.3
xdotool key Escape
xdotool mousemove 1000 700
sleep 0.4
xdotool mousemove "$ox" "$oy"
sleep 0.2
xdotool mousemove $((ox + 1)) "$oy"
sleep 2.2
import -window root "$out-tip.png"
echo "$kit $theme done"
