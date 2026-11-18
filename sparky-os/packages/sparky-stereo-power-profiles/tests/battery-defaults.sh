#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# The battery and brightness defaults (ORDER 668) as KConfig reads them, below the person's own file.
# Needs kreadconfig6 (libkf6config-bin). usage: battery-defaults.sh PACKAGE_FOLDER|none
set -u
SRC=${1:?usage: battery-defaults.sh PACKAGE_FOLDER|none}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/etc/xdg" "$W/home/.config"
[ "$SRC" = none ] || cp "$SRC/share/powerdevilrc" "$W/etc/xdg/powerdevilrc"
rk() { g1=$1; shift; if [ "$#" = 3 ]; then HOME=$W/home XDG_CONFIG_HOME=$W/home/.config XDG_CONFIG_DIRS=$W/etc/xdg kreadconfig6 --file powerdevilrc --group "$g1" --group "$1" --key "$2" --default "$3"; else HOME=$W/home XDG_CONFIG_HOME=$W/home/.config XDG_CONFIG_DIRS=$W/etc/xdg kreadconfig6 --file powerdevilrc --group "$g1" --key "$1" --default "$2"; fi; }
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1: $2"; else echo "FAIL $1: got $2, wanted $3"; fail=1; fi; }
check "low battery level" "$(rk BatteryManagement BatteryLowLevel unset)" 25
check "critical battery level" "$(rk BatteryManagement BatteryCriticalLevel unset)" 15
check "critical battery action (8 is shut down)" "$(rk BatteryManagement BatteryCriticalAction unset)" 8
check "screen on mains" "$(rk AC Display DisplayBrightness unset)" 100
check "keyboard light on mains" "$(rk AC Keyboard KeyboardBrightness unset)" 100
check "keyboard light on low battery" "$(rk LowBattery Keyboard KeyboardBrightness unset)" 11
check "the earlier defaults are still there (sleep then hibernate on battery)" "$(rk Battery SuspendAndShutdown SleepMode unset)" 3
check "the earlier defaults are still there (dim on mains)" "$(rk AC Display DimDisplayIdleTimeoutSec unset)" 900
printf '[BatteryManagement]\nBatteryLowLevel=10\n' > "$W/home/.config/powerdevilrc"
check "the person's own level wins" "$(rk BatteryManagement BatteryLowLevel unset)" 10
exit $fail
