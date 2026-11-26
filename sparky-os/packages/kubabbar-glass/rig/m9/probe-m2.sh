#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# DESKTOP_PROBE for the stereo-proof-rig's login-splash/login.sh, Kubabbar Glass 9 milestone 2: STEPS is a list of
# session2.py steps ("panels:NAME keep greeter qt5 gtk") and of milestone 1's probe steps ("glass") run in this login.
set -u
RIG=${RIG:-/rig-scripts}
M9=${M9:-/m9}
log() { echo "$(date -u +%H:%M:%S.%N) $*" >> "$CASE/probe-m2.log"; }
export QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0
for step in ${STEPS:-panels:panels}; do
	case $step in
	glass)
		STEPS="panel notif launcher windows" bash "$RIG/translucency-probe/probe.sh"
		python3 "${LT:-/lt}/analyze.py" "$CASE" > "$CASE/glass.json" 2>>"$CASE/probe-m2.log"
		log "glass done" ;;
	panels:*)
		python3 "$M9/session2.py" panels "${step#panels:}" >> "$CASE/probe-m2.log" 2>&1 || log "FAIL $step" ;;
	panelshot:*)
		python3 "$M9/session2.py" panelshot "${step#panelshot:}" >> "$CASE/probe-m2.log" 2>&1 || log "FAIL $step" ;;
	*)
		python3 "$M9/session2.py" "$step" >> "$CASE/probe-m2.log" 2>&1 || log "FAIL $step" ;;
	esac
done
log "probe-m2 done"
