#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# DESKTOP_PROBE for the stereo-proof-rig's login-splash/login.sh: inside a real login with Kubabbar Glass 9 applied.
# Env: CASE, STEPS ("glass widget apps fonts"), M9 (this folder, mounted), RIG (the rig's scripts, at /rig-scripts).
#   glass   the translucency probe (panel, notification, launcher pop-up, an inactive window, a dialog) over black and white
#   widget  a desktop widget over black and white, its frame from Plasma's scripting
#   apps    Dolphin, Konsole, System Settings, Kate and the gallery in Qt 6 and Qt 5, placed by KWin; Dolphin active;
#           one capture (both eyes on a 3D output), the windows' frames beside it
#   fonts   what Qt resolves for the session's fonts, what fontconfig gives for the classic names, the helper's record
set -u
RIG=${RIG:-/rig-scripts}
M9=${M9:-/m9}
P="python3 $RIG/translucency-probe/probe.py"
log() { echo "$(date -u +%H:%M:%S.%N) $*" >> "$CASE/probe9.log"; }
export QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0
for step in ${STEPS:-glass widget apps fonts}; do
	case $step in
	glass)
		STEPS="panel notif launcher windows" bash "$RIG/translucency-probe/probe.sh"
		python3 "${LT:-/lt}/analyze.py" "$CASE" > "$CASE/glass.json" 2>>"$CASE/probe9.log"
		log "glass done" ;;
	widget)
		python3 "$M9/session.py" widget >> "$CASE/probe9.log" 2>&1 || log "FAIL widget" ;;
	apps)
		python3 "$M9/session.py" apps >> "$CASE/probe9.log" 2>&1 || log "FAIL apps" ;;
	fonts)
		python3 "$M9/session.py" fonts >> "$CASE/probe9.log" 2>&1 || log "FAIL fonts" ;;
	esac
done
log "probe9 done"
