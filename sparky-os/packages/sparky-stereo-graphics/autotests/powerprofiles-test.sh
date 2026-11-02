#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# powerprofilestest and the command line against a private bus carrying fake-ppd.py (browsers: the kind that follows the profile).
set -u
BIN=${BIN:?}
SRC=${SRC:?}
T=$(mktemp -d)
trap 'kill $PPD $BUS 2>/dev/null; rm -rf "$T"' EXIT
cat >"$T/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$T/bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
CONF
dbus-daemon --config-file="$T/bus.conf" --nofork >"$T/bus.log" 2>&1 &
BUS=$!
for i in $(seq 1 50); do [ -S "$T/bus" ] && break; sleep 0.1; done
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$T/bus" PPD_STATE=$T/ppd-state
python3 -I "$SRC/autotests/fake-ppd.py" performance "$PPD_STATE" >"$T/ppd.log" 2>&1 &
PPD=$!
for i in $(seq 1 50); do grep -q ready "$T/ppd.log" && break; sleep 0.1; done
grep -q ready "$T/ppd.log" || { cat "$T/ppd.log"; exit 1; }
"$BIN/powerprofilestest" || exit 1
# the command line reads the profile from the daemon too
"$BIN/makefixture" host "$T/host" || exit 1
export XDG_CONFIG_HOME=$T/c XDG_CONFIG_DIRS=$T/c XDG_DATA_HOME=$T/d XDG_DATA_DIRS=$T/u
got=$(SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$BIN/sparky-stereo-gpu-env" --category browsers --print gpu)
[ "$got" = "NVIDIA GeForce RTX 3060 Lite Hash Rate" ] || { echo "FAIL cli profile from the daemon: $got"; exit 1; }
echo "powerprofiles: cli follows the daemon's performance profile"
# the daemon gone, on a bus that still runs, and no bus at all: said, never Balanced in its place (ORDER 346a, U24);
# browsers follow the profile, so they cannot be placed, and say why; an explicit profile is honoured
kill $PPD; wait $PPD 2>/dev/null
got=$(SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$BIN/sparky-stereo-gpu-env" --category browsers --print gpu 2>"$T/err"); rc=$?
[ "$rc" = 4 ] && [ -z "$got" ] && grep -q 'power-profiles-daemon is not running' "$T/err" || { echo "FAIL cli without the daemon: rc=$rc '$got' $(cat "$T/err")"; exit 1; }
got=$(DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/bus SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$BIN/sparky-stereo-gpu-env" --category browsers --print gpu 2>"$T/err"); rc=$?
[ "$rc" = 4 ] && grep -q 'the system bus cannot be reached' "$T/err" || { echo "FAIL cli without a bus: rc=$rc '$got' $(cat "$T/err")"; exit 1; }
got=$(DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/bus SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$BIN/sparky-stereo-gpu-env" --category browsers --profile balanced --print gpu)
[ "$got" = "AMD Radeon Vega Series / Radeon Vega Mobile Series" ] || { echo "FAIL an explicit profile without a bus: $got"; exit 1; }
got=$(DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/bus SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$BIN/sparky-stereo-gpu-env" --category other --print gpu)
[ "$got" = "AMD Radeon Vega Series / Radeon Vega Mobile Series" ] || { echo "FAIL other programs need no profile: $got"; exit 1; }
echo "powerprofiles: without the daemon or the bus the profile is said, not Balanced; an explicit profile is honoured"
