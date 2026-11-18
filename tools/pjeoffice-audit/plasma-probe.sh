#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu
if [ "${PJ18_SESSION_ENV:-}" != 1 ]; then exec python3 /scratch/session-env.py "$0"; fi
mkdir -p "$CASE/probe"
APP=/scratch/unpacked/pjeoffice-pro
cd "$APP"
QT_QPA_PLATFORM=xcb xembedsniproxy > "$CASE/probe/xembed.log" 2>&1 & proxy_pid=$!
sleep 2
qdbus6 org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher.IsStatusNotifierHostRegistered > "$CASE/probe/host-registered.txt"
python3 - <<'PROBE'
from Xlib import display
from pathlib import Path
import os
d=display.Display()
a=d.intern_atom('_NET_SYSTEM_TRAY_S0')
Path(os.environ['CASE']+'/probe/xembed-owner.txt').write_text(str(d.get_selection_owner(a))+'\n')
PROBE
./jre/bin/java -cp /scratch/probe-classes:pjeoffice-pro.jar TrayProbe > "$CASE/probe/tray-policy.txt" 2>&1
./jre/bin/java -Xmx2048m -Duser.home="$HOME" -Dpjeoffice_home="$APP" -Dffmpeg_home="$APP" -Dpjeoffice_looksandfeels=Metal -Dcutplayer4j_looksandfeels=Nimbus -Dsigner4j_a3auto=true -jar pjeoffice-pro.jar > "$CASE/probe/application.log" 2>&1 & app_pid=$!
trap 'kill "$app_pid" "$proxy_pid" 2>/dev/null || true' EXIT
sleep 5
qdbus6 org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems > "$CASE/probe/tray-items.txt"
qdbus6 org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.freedesktop.DBus.Introspectable.Introspect > "$CASE/probe/tray-interface.xml"
xdotool search --name '.*' getwindowname %@ > "$CASE/probe/windows.txt" || true
curl -sS -i --max-time 4 -X PUT -H 'Content-Type: application/json' -H 'Force-Preflight: true' -H 'Origin: http://127.0.0.1:8800' 'http://127.0.0.1:8800/pjeOffice/?u=18' > "$CASE/probe/ping.txt"
