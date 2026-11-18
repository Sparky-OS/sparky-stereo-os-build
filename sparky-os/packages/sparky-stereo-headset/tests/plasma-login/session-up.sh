#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Inside the rig container, as the user `rig`: a Plasma login in the order of a real one (private session bus, KWin on a virtual 1600x900 output,
# kactivitymanagerd, plasmashell) with one panel (launcher, spacer, system tray, clock), and the environment written to ~/env.sh so that later
# `docker exec` commands act in the same session. PATH starts with the folder in $STANDIN (the program's stand-in, or the real one on its test device).
# Options: HS_STANDIN_DIR (the stand-in's state folder, default /tmp/hs-standin); POWERDEVIL=1 starts PowerDevil too (it needs the system bus, UPower on it,
# and writes every notification of the session to $XDG_RUNTIME_DIR/notify.log); POPUPS=/path/popups.js loads the KWin script that logs popup windows.
# Usage: STANDIN=/t/standin session-up.sh
set -uo pipefail
export HOME=/home/rig LANG=C.UTF-8 LC_ALL=C.UTF-8
export XDG_RUNTIME_DIR=/tmp/xdg-rig; mkdir -p "$XDG_RUNTIME_DIR" "$HOME/.config"; chmod 700 "$XDG_RUNTIME_DIR"
unset DISPLAY WAYLAND_DISPLAY
svc=$XDG_RUNTIME_DIR/dbus-services; mkdir -p "$svc"
for f in /usr/share/dbus-1/services/*.service; do
	case $(basename "$f") in org.kde.kded6.service | org.kde.runners.baloo.service | org.kde.krunner.service | org.kde.KSplash.service) ;; *) ln -sf "$f" "$svc/" ;; esac
done
sed "s#<standard_session_servicedirs */>#<servicedir>$svc</servicedir>#" /usr/share/dbus-1/session.conf >"$XDG_RUNTIME_DIR/session.conf"
eval "$(dbus-launch --config-file="$XDG_RUNTIME_DIR/session.conf" --sh-syntax)"
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1
export PATH="${STANDIN:?}:$PATH" HS_STANDIN_DIR=${HS_STANDIN_DIR:-/tmp/hs-standin}
printf '[Daemon]\nAutolock=false\nLockOnResume=false\nTimeout=0\n' >"$HOME/.config/kscreenlockerrc"
printf '[Windows]\nFocusPolicy=FocusFollowsMouse\nClickRaise=true\n' >"$HOME/.config/kwinrc"
cp /usr/bin/kwin_wayland "$XDG_RUNTIME_DIR/kwin_wayland"   # a copy without the file capability (the container has no CAP_SYS_NICE)
QT_LOGGING_RULES="kwin_scripting.debug=true;js.debug=true" QT_QPA_PLATFORM=offscreen "$XDG_RUNTIME_DIR/kwin_wayland" --virtual --socket=wl-test --width 1600 --height 900 >"$XDG_RUNTIME_DIR/kwin.log" 2>&1 &
for _ in $(seq 300); do [ -S "$XDG_RUNTIME_DIR/wl-test" ] && break; sleep 0.2; done
export WAYLAND_DISPLAY=wl-test
if [ -n "${POPUPS:-}" ]; then sleep 2; r=$(dbus-send --session --print-reply --dest=org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript string:"$POPUPS" string:popups); sid=${r##* }; dbus-send --session --print-reply --dest=org.kde.KWin /Scripting/Script$sid org.kde.kwin.Script.run >/dev/null; fi
cat >"$HOME/env.sh" <<ENV
export HOME=$HOME LANG=C.UTF-8 LC_ALL=C.UTF-8 XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS='$DBUS_SESSION_BUS_ADDRESS' WAYLAND_DISPLAY=wl-test
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 PATH='$PATH' HS_STANDIN_DIR=$HS_STANDIN_DIR
export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland
ENV
QT_QPA_PLATFORM=wayland /usr/lib/x86_64-linux-gnu/libexec/kactivitymanagerd >"$XDG_RUNTIME_DIR/kactivities.log" 2>&1 &
sleep 1
env XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6 XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland plasmashell >"$XDG_RUNTIME_DIR/plasmashell.log" 2>&1 &
for _ in $(seq 300); do dbus-send --session --dest=org.freedesktop.DBus --print-reply /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner string:org.kde.plasmashell 2>/dev/null | grep -q true && break; sleep 0.2; done
sleep 4
cat >"$XDG_RUNTIME_DIR/panel.js" <<'JS'
panels().forEach(function (p) { p.remove(); });
var p = new Panel; p.location = "bottom"; p.height = 44;
p.addWidget("org.kde.plasma.kickoff"); p.addWidget("org.kde.plasma.panelspacer"); p.addWidget("org.kde.plasma.systemtray"); p.addWidget("org.kde.plasma.digitalclock");
JS
dbus-send --session --print-reply --dest=org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript string:"$(cat "$XDG_RUNTIME_DIR/panel.js")" >/dev/null
sleep 3
if [ -n "${POWERDEVIL:-}" ]; then
	dbus-monitor --session "interface='org.freedesktop.Notifications',member='Notify'" >"$XDG_RUNTIME_DIR/notify.log" 2>&1 &
	QT_QPA_PLATFORM=wayland /usr/lib/x86_64-linux-gnu/libexec/org_kde_powerdevil >"$XDG_RUNTIME_DIR/powerdevil.log" 2>&1 &
	sleep 4
fi
[ -S "$XDG_RUNTIME_DIR/wl-test" ] && pgrep -x plasmashell >/dev/null && echo up >"$XDG_RUNTIME_DIR/up"
sleep infinity
