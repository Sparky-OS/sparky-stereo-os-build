#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# The session defaults (ORDER 668) as KConfig reads them: /etc/xdg/ksmserverrc below the person's own file, and the
# layout's launcher. Needs kreadconfig6 (libkf6config-bin). usage: session-defaults.sh PACKAGE_FOLDER|none
set -u
SRC=${1:?usage: session-defaults.sh PACKAGE_FOLDER|none}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/etc/xdg" "$W/home/.config"
[ "$SRC" = none ] || cp "$SRC/default/xdg/ksmserverrc" "$W/etc/xdg/ksmserverrc"
read_key() { HOME=$W/home XDG_CONFIG_HOME=$W/home/.config XDG_CONFIG_DIRS=$W/etc/xdg kreadconfig6 --file ksmserverrc --group General --key "$1" --default "$2"; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1: $2"; else echo "FAIL $1: got $2, wanted $3"; fail=1; fi; }
check "a session starts empty" "$(read_key loginMode restorePreviousLogout)" emptySession
check "logging out asks no confirmation" "$(read_key confirmLogout true)" false
printf '[General]\nloginMode=restorePreviousLogout\nconfirmLogout=true\n' > "$W/home/.config/ksmserverrc"
check "the person's own session choice wins" "$(read_key loginMode x)" restorePreviousLogout
check "the person's own confirmation choice wins" "$(read_key confirmLogout x)" true
[ "$SRC" = none ] || cp "$SRC/default/xdg/kdeglobals" "$W/etc/xdg/kdeglobals"
check "the sound theme is Oxygen" "$(HOME=$W/home XDG_CONFIG_HOME=$W/home/.config XDG_CONFIG_DIRS=$W/etc/xdg kreadconfig6 --file kdeglobals --group Sounds --key Theme --default ocean)" oxygen
if [ "$SRC" != none ]; then
	L=$SRC/default/org.sparkystereo.desktop/contents/layouts/org.kde.plasma.desktop-layout.js
	check "the layout adds the Application Menu" "$(grep -c 'addWidget("org.kde.plasma.kicker")' "$L")" 1
	check "the layout adds no Kickoff and loads no template" "$(grep -c -E 'org.kde.plasma.kickoff"|loadTemplate' "$L")" 0
	check "the layout's widgets in KDE's order" "$(grep -o 'addWidget("[a-z.]*")' "$L" | sed 's/addWidget("org.kde.plasma.//; s/")//' | tr '\n' ' ')" "kicker pager icontasks marginsseparator kimpanel systemtray digitalclock showdesktop "
fi
exit $fail
