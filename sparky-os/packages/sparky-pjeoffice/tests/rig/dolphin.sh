#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As the person in a container with the package installed, no network, a private Xvfb: Dolphin on a folder with one PDF, the context menu of the file opened with the
# keyboard's menu key, a picture of it, and the action's own command line read from the menu entry file. Usage: dolphin.sh OUT
set -u
OUT=${1:?}; mkdir -p "$OUT" "$HOME/docs"; ulimit -c 0
export OUT DISPLAY=:98 LANG=${LOGIN_LANG:-C.UTF-8} QT_QPA_PLATFORM=xcb
Xvfb :98 -screen 0 1280x800x24 -nolisten tcp > "$OUT/xvfb.log" 2>&1 &
sleep 1
printf '%%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\ntrailer<</Root 1 0 R>>\n%%%%EOF\n' > "$HOME/docs/document.pdf"
cat > $OUT/inner.sh <<'IN'
dolphin "$HOME/docs" > "$OUT/dolphin.log" 2>&1 &
for i in $(seq 40); do xdotool search --name 'docs' >/dev/null 2>&1 && break; sleep 1; done
sleep 6
xdotool mousemove 640 400 click 1
sleep 1
xdotool key ctrl+a
sleep 1
xdotool key Menu
sleep 3
import -window root "$OUT/dolphin-context-menu.png"
xdotool search --name '.' getwindowname %@ | sort | uniq -c > "$OUT/dolphin-windows.txt"
IN
dbus-run-session -- bash $OUT/inner.sh
grep -E "^(Exec|Name|MimeType|Actions|X-KDE-Priority)" /usr/share/kio/servicemenus/sparky-pjeoffice-sign.desktop > "$OUT/servicemenu-entry.txt"
kill %1 2>/dev/null
