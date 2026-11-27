#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# DESKTOP_PROBE for the stereo-proof-rig's login-splash/login.sh, Kubabbar Glass 9 milestone 3: STEPS is a list of
# session3.py steps ("bars greeter-family dock") and of session2.py's ("panels:NAME panelshot:NAME") run in this login.
set -u
M9=${M9:-/m9}
log() { echo "$(date -u +%H:%M:%S.%N) $*" >> "$CASE/probe-m3.log"; }
export QT_QPA_PLATFORM=wayland WAYLAND_DISPLAY=wayland-0
for step in ${STEPS:-bars}; do
	case $step in
	panels:*)
		python3 "$M9/session2.py" panels "${step#panels:}" >> "$CASE/probe-m3.log" 2>&1 || log "FAIL $step" ;;
	panelshot:*)
		python3 "$M9/session2.py" panelshot "${step#panelshot:}" >> "$CASE/probe-m3.log" 2>&1 || log "FAIL $step" ;;
	*)
		python3 "$M9/session3.py" "$step" >> "$CASE/probe-m3.log" 2>&1 || log "FAIL $step" ;;
	esac
done
log "probe-m3 done"
