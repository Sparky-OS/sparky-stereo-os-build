#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Guest only, root, in the development VM with the Plasma session on tty3:
# does PowerDevil's idle timeline fire with the installed KIdleTime?
#   guest-idle-ab.sh LABEL   (prints one JSON line; restores the user config)
set -u
U="runuser -u daniel -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus WAYLAND_DISPLAY=wayland-0"
label=$1
cfg=/home/daniel/.config/powerdevilrc
cp -p $cfg /var/tmp/powerdevilrc.ab
loginctl unlock-session 1; $U kscreen-doctor --dpms on >/dev/null 2>&1; sleep 1
$U systemctl --user restart plasma-powerdevil; sleep 4
since=$(date '+%F %T')
$U kwriteconfig6 --file powerdevilrc --group AC --group Display --key DimDisplayIdleTimeoutSec 10
$U kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 30
$U kwriteconfig6 --file powerdevilrc --group AC --group Display --key LockBeforeTurnOffDisplay true
$U busctl --user call org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement refreshStatus
sleep 45
dpms=$($U python3 /var/tmp/guest-tty.py --dpms /run/user/1000/wayland-0)
locked=$($U busctl --user call org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver GetActive)
mismatch=$(journalctl -q --no-pager --since "$since" _UID=1000 -t org_kde_powerdevil | grep -c "revision mismatch")
mismatch_start=$(journalctl -q --no-pager -b _UID=1000 -t org_kde_powerdevil | grep -c "revision mismatch")
events=$(journalctl -q --no-pager --since "$since" _UID=1000 -t org_kde_powerdevil | grep -E "triggered on idle timeout" | sed 's/.*powerdevil: //' | tr '\n' ';')
echo "{\"kidletime\": \"$(dpkg-query -W -f='${Version}' libkf6idletime6)\", \"label\": \"$label\", \"dpms_after_45s\": $dpms, \"screensaver_active\": \"$locked\", \"powerdevil_idle_events\": \"$events\", \"qt_revision_mismatch_lines_this_boot\": $mismatch_start}"
install -o daniel -g daniel -m 600 /var/tmp/powerdevilrc.ab $cfg
$U busctl --user call org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement org.kde.Solid.PowerManagement refreshStatus
loginctl unlock-session 1; $U kscreen-doctor --dpms on >/dev/null 2>&1
