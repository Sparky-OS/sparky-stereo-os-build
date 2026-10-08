#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL2 License
# Last update 2026/10/08
set -euo pipefail
ulimit -c 0
[[ -e /.dockerenv ]]
: "${POWERDEVIL_SOURCE:?Set POWERDEVIL_SOURCE to the patched source tree}"
: "${PLASMA_WORKSPACE_SOURCE:?Set PLASMA_WORKSPACE_SOURCE to its source tree}"
: "${TIMELINE_WORK:?Set TIMELINE_WORK to scratch inside this workspace}"
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$TIMELINE_WORK"
cmake -S "$HERE" -B "$TIMELINE_WORK"/timeline-build -DBUILD_TIMELINE_PROBE=ON -DPOWERDEVIL_SOURCE="$POWERDEVIL_SOURCE" -DPLASMA_WORKSPACE_SOURCE="$PLASMA_WORKSPACE_SOURCE"
cmake --build "$TIMELINE_WORK"/timeline-build -j4
export QT_QPA_PLATFORM=offscreen XDG_CONFIG_HOME=$TIMELINE_WORK/timeline-config XDG_CONFIG_DIRS=${TIMELINE_DEFAULTS:-$HERE/../candidate-defaults}
profile_args=()
if [[ ${TIMELINE_PROFILES:-0} == 1 ]]; then profile_args=(--profiles); fi
mkdir -p "$XDG_CONFIG_HOME"
dbus-daemon --session --fork --print-address --print-pid >"$TIMELINE_WORK"/timeline-bus
export DBUS_SYSTEM_BUS_ADDRESS=$(head -n 1 "$TIMELINE_WORK"/timeline-bus)
bus_pid=$(tail -n 1 "$TIMELINE_WORK"/timeline-bus)
hardware_pid=
trap 'kill "${hardware_pid:-}" "$bus_pid" 2>/dev/null || true; wait "${hardware_pid:-}" 2>/dev/null || true' EXIT
for hardware in desktop laptop peripheral ups laptop-no-battery; do
 extra=()
 fixture=$hardware
 case $hardware in
 laptop) extra=(--laptop --supply);;
 ups) extra=(--supply);;
 laptop-no-battery) extra=(--laptop); fixture=desktop;;
 esac
 : >"$TIMELINE_WORK"/timeline-hardware.log
 "$TIMELINE_WORK"/timeline-build/timeline-hardware "${extra[@]}" >"$TIMELINE_WORK"/timeline-hardware.log 2>&1 &
 hardware_pid=$!
 for attempt in {1..100}; do
  if grep -q READY "$TIMELINE_WORK"/timeline-hardware.log; then break; fi
  sleep 0.02
 done
 grep -q READY "$TIMELINE_WORK"/timeline-hardware.log
 SOLID_FAKEHW="$HERE/hardware/$fixture.xml" "$TIMELINE_WORK"/timeline-build/timeline-probe "${extra[@]}" "${profile_args[@]}" >"$TIMELINE_WORK/timeline-$hardware.log" 2>&1
 kill "$hardware_pid"
 wait "$hardware_pid" || true
 hardware_pid=
done
: >"$TIMELINE_WORK"/timeline-hardware.log
"$TIMELINE_WORK"/timeline-build/timeline-hardware >"$TIMELINE_WORK"/timeline-hardware.log 2>&1 &
hardware_pid=$!
for attempt in {1..100}; do
 if grep -q READY "$TIMELINE_WORK"/timeline-hardware.log; then break; fi
 sleep 0.02
done
grep -q READY "$TIMELINE_WORK"/timeline-hardware.log
mkdir -p "$TIMELINE_WORK"/timeline-user
cat > "$TIMELINE_WORK"/timeline-user/powerdevilrc <<'CONFIG'
[AC][Display]
DimDisplayIdleTimeoutSec=901
TurnOffDisplayIdleTimeoutSec=3600
[AC][SuspendAndShutdown]
AutoSuspendAction=1
AutoSuspendIdleTimeoutSec=7200
CONFIG
XDG_CONFIG_HOME=$TIMELINE_WORK/timeline-user SOLID_FAKEHW=$HERE/hardware/desktop.xml "$TIMELINE_WORK"/timeline-build/timeline-probe --user "${profile_args[@]}" >"$TIMELINE_WORK"/timeline-user.log 2>&1
printf 'PASS real ProfileSettings desktop, UPS desktop, laptop, battery-less laptop, peripheral battery, tablet modes, VM, capability and user overrides\n' >"$TIMELINE_WORK"/timeline-tests.result
