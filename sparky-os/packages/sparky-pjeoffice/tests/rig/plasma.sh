#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As the person (uid 1000) in a container with the packages installed, no network, no device: a real startplasma-wayland login on KWin's virtual QPainter backend.
# The package's autostart entry starts the tray and the signer at login. Records the tray items the session's host registered, the signer's answer, and captures
# the compositor's own output buffer (capture-qpainter.py) of the desktop and of the package's System Settings page.
# Usage: plasma.sh OUT   Needs /rig (this folder)
set -u
OUT=${1:?result folder}; mkdir -p "$OUT"; ulimit -c 0
export XDG_RUNTIME_DIR=/tmp/r$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export LANG=${LOGIN_LANG:-C.UTF-8} LANGUAGE=${LOGIN_LANGUAGE:-} OUT KWIN_VIRTUAL_STEREO_MODES=0 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export QT_QPA_PLATFORM=wayland
mkdir -p $XDG_RUNTIME_DIR/shim
cat > $XDG_RUNTIME_DIR/shim/kwin_wayland <<SH
#!/bin/sh
exec /usr/bin/kwin_wayland "\$@" --virtual --output-count 1 --width 1280 --height 800
SH
chmod +x $XDG_RUNTIME_DIR/shim/kwin_wayland
export PATH=$XDG_RUNTIME_DIR/shim:$PATH
mkdir -p "$HOME/.config"
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
kwriteconfig6 --file ksmserverrc --group General --key loginMode emptySession
cat > $XDG_RUNTIME_DIR/inner.sh <<'IN'
set -u
# KWin has file capabilities, so its buffers are readable only by root: the container's root side (capture-daemon.sh) takes the picture on request
capture() { echo "$XDG_RUNTIME_DIR" > "$OUT/want-$1"; for _ in $(seq 60); do [ -s "$OUT/$1.png" ] && return 0; sleep 1; done; echo "no capture $1" >> "$OUT/capture-errors.txt"; }
setsid startplasma-wayland > "$OUT/session.log" 2>&1 &
SP=$!
for i in $(seq 120); do pgrep -u $(id -u) -x plasmashell >/dev/null && break; sleep 1; done
sleep 20
PS=$(pgrep -u $(id -u) -x plasmashell | head -1)
for k in WAYLAND_DISPLAY DISPLAY XAUTHORITY; do v=$(tr '\0' '\n' < /proc/$PS/environ | grep "^$k=" | cut -d= -f2-); [ -n "$v" ] && export $k="$v"; done
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY DISPLAY=${DISPLAY:-}" > "$OUT/env.txt"
export KWIN_PID=$(pgrep -u $(id -u) -x kwin_wayland | head -1)
export KWIN_CAPTURE_WIDTH=1280 KWIN_CAPTURE_HEIGHT=800
qdbus6 org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher.IsStatusNotifierHostRegistered > "$OUT/host-registered.txt" 2>&1
qdbus6 org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems > "$OUT/tray-items.txt" 2>&1
sparky-pjeoffice status > "$OUT/status.txt" 2>&1
pgrep -a -u $(id -u) -f 'sparky-pjeoffice-tray|PjeOfficePROUser' | cut -c1-120 > "$OUT/processes.txt"
capture desktop
# the page of the package in System Settings, its own window
(kcmshell6 kcm_sparkystereo_pjeoffice > "$OUT/kcmshell.log" 2>&1 &)
sleep 12
capture settings-page
cp -r "$HOME/.local/state/sparky-pjeoffice" "$OUT/state" 2>/dev/null
kill -TERM $SP 2>/dev/null; sleep 2
IN
dbus-run-session -- bash $XDG_RUNTIME_DIR/inner.sh
rm -rf "$XDG_RUNTIME_DIR"
