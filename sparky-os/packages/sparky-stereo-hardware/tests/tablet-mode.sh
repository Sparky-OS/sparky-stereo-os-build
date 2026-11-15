#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Tests bin/sparky-stereo-has-tablet-mode and share/plasma-env/sparky-stereo-tablet-mode.sh on fixture sysfs trees, and
# what KConfig then reads (kreadconfig6, when installed): the default on a convertible, the person's own choice over it,
# nothing on a computer without a tablet mode.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
# input SYS N PROPERTIES ABS KEY SW: one input device, each a sysfs bitmap as the kernel prints it
input() {
	d=$1/class/input/input$2; mkdir -p "$d/capabilities"
	echo "$3" > "$d/properties"; echo "$4" > "$d/capabilities/abs"; echo "$5" > "$d/capabilities/key"; echo "$6" > "$d/capabilities/sw"
}
chassis() { mkdir -p "$1/class/dmi/id"; echo "$2" > "$1/class/dmi/id/chassis_type"; }
# devices shaped as the kernel describes them (the bit numbers are linux/input-event-codes.h's)
touchscreen() { input "$1" "$2" 2 '260800000000003' '400 0 0 0 0 0' 0; }            # multitouch screen: direct, ABS_X ABS_Y, ABS_MT_POSITION_*, BTN_TOUCH
touchpad() { input "$1" "$2" 5 '260800000000003' 'e520 10000 0 0 0 0' 0; }           # pointer and buttonpad: not direct
pen_display() { input "$1" "$2" 2 '1000003' '1c03 0 0 0 0 0' 0; }                     # direct, with BTN_TOOL_PEN and BTN_STYLUS
keyboard() { input "$1" "$2" 0 0 '402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe' 0; }
lid() { input "$1" "$2" 0 0 0 1; }                                                    # SW_LID only
tablet_switch() { input "$1" "$2" 0 0 0 2; }                                          # SW_TABLET_MODE
lid_and_tablet_switch() { input "$1" "$2" 0 0 0 3; }
has() { SPARKY_STEREO_SYSFS=$1 "$HERE/bin/sparky-stereo-has-tablet-mode"; echo $?; }
why() { SPARKY_STEREO_SYSFS=$1 "$HERE/bin/sparky-stereo-has-tablet-mode" --why; }

s=$T/convertible; keyboard $s 0; touchpad $s 1; touchscreen $s 2; lid_and_tablet_switch $s 3; chassis $s 10
check "a notebook with a touch screen and a tablet-mode switch" "$(has $s)" 0
check "and why" "$(why $s)" "touch screen: yes; tablet-mode switch: yes; chassis type: 10"
s=$T/slider; keyboard $s 0; touchpad $s 1; touchscreen $s 2; tablet_switch $s 3; chassis $s 31
check "a convertible chassis with the switch" "$(has $s)" 0
s=$T/tablet; touchscreen $s 0; chassis $s 30
check "a tablet: a touch screen and a tablet chassis, no switch" "$(has $s)" 0
check "and why" "$(why $s)" "touch screen: yes; tablet-mode switch: no; chassis type: 30 (tablet)"
s=$T/detachable; touchscreen $s 0; keyboard $s 1; chassis $s 32
check "a detachable" "$(has $s)" 0
s=$T/touch-laptop; keyboard $s 0; touchpad $s 1; touchscreen $s 2; lid $s 3; chassis $s 10
check "a notebook with a touch screen, a lid and no tablet mode" "$(has $s)" 1
s=$T/laptop; keyboard $s 0; touchpad $s 1; lid $s 2; chassis $s 10
check "a notebook without a touch screen" "$(has $s)" 1
s=$T/switch-no-touch; keyboard $s 0; touchpad $s 1; lid_and_tablet_switch $s 2; chassis $s 31
check "a switch and a convertible chassis, no touch screen" "$(has $s)" 1
s=$T/desktop-touch; keyboard $s 0; touchscreen $s 1; chassis $s 3
check "a desktop with a touch monitor" "$(has $s)" 1
s=$T/pen; keyboard $s 0; pen_display $s 1; tablet_switch $s 2; chassis $s 31
check "a pen display is not a touch screen" "$(has $s)" 1
s=$T/desktop; keyboard $s 0; chassis $s 3
check "a desktop" "$(has $s)" 1
s=$T/empty; mkdir -p $s
check "a /sys with nothing to read" "$(has $s)" 1
check "and why" "$(why $s)" "touch screen: no; tablet-mode switch: no; chassis type: unknown"

# the env script: the folder of defaults goes first, once, and only on a computer with a tablet mode
D=$HERE/share/tablet-mode/xdg
env_of() { (SPARKY_STEREO_SYSFS=$1; export SPARKY_STEREO_SYSFS; SPARKY_STEREO_HAS_TABLET_MODE=$HERE/bin/sparky-stereo-has-tablet-mode SPARKY_STEREO_TABLET_MODE_DIR=$D
	[ "$2" = unset ] && unset XDG_CONFIG_DIRS || XDG_CONFIG_DIRS=$2
	. "$HERE/share/plasma-env/sparky-stereo-tablet-mode.sh"; echo "${XDG_CONFIG_DIRS:-unset}"; echo "${_sp_tablet:-clean}"); }
check "convertible, XDG_CONFIG_DIRS unset" "$(env_of $T/convertible unset | head -1)" "$D:/etc/xdg"
check "convertible, XDG_CONFIG_DIRS set" "$(env_of $T/convertible /etc/xdg/xdg-plasma:/etc/xdg | head -1)" "$D:/etc/xdg/xdg-plasma:/etc/xdg"
check "convertible, the folder already there" "$(env_of $T/convertible "$D:/etc/xdg" | head -1)" "$D:/etc/xdg"
check "notebook, XDG_CONFIG_DIRS unset" "$(env_of $T/laptop unset | head -1)" unset
check "notebook, XDG_CONFIG_DIRS set" "$(env_of $T/laptop /etc/xdg | head -1)" /etc/xdg
check "the script leaves no variable of its own" "$(env_of $T/convertible unset | tail -1)" clean

# what KConfig reads, as KWin and System Settings do
if command -v kreadconfig6 >/dev/null 2>&1; then
	K=/usr/share/applications/org.kde.plasma.keyboard.desktop
	read_im() { # read_im SYS: the session's InputMethod with $XDG_CONFIG_HOME as the person's folder
		(SPARKY_STEREO_SYSFS=$1; export SPARKY_STEREO_SYSFS; SPARKY_STEREO_HAS_TABLET_MODE=$HERE/bin/sparky-stereo-has-tablet-mode SPARKY_STEREO_TABLET_MODE_DIR=$D
		unset XDG_CONFIG_DIRS; . "$HERE/share/plasma-env/sparky-stereo-tablet-mode.sh"
		kreadconfig6 --file kwinrc --group Wayland --key InputMethod --default none); }
	export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config; mkdir -p "$XDG_CONFIG_HOME"
	check "convertible, a new person" "$(read_im $T/convertible)" "$K"
	check "notebook, a new person" "$(read_im $T/laptop)" none
	printf '[Wayland]\nInputMethod=/usr/share/applications/org.fcitx.Fcitx5.desktop\n' > "$XDG_CONFIG_HOME/kwinrc"
	check "convertible, the person chose another keyboard" "$(read_im $T/convertible)" /usr/share/applications/org.fcitx.Fcitx5.desktop
	printf '[Wayland]\nInputMethod=\n' > "$XDG_CONFIG_HOME/kwinrc"
	check "convertible, the person chose None" "$(read_im $T/convertible)" ""
	printf '[Windows]\nFocusPolicy=ClickToFocus\n' > "$XDG_CONFIG_HOME/kwinrc"
	check "convertible, a kwinrc of the person's without the key" "$(read_im $T/convertible)" "$K"
	check "and the person's other keys stay" "$(XDG_CONFIG_DIRS=$D:/etc/xdg kreadconfig6 --file kwinrc --group Windows --key FocusPolicy)" ClickToFocus
else
	echo "tablet-mode: kreadconfig6 is not installed, the KConfig rows were not run"
	[ "${SPARKY_STEREO_NEED_KCONFIG:-0}" = 0 ] || fail=$((fail + 1))
fi
echo "tablet-mode: $pass passed, $fail failed"
[ "$fail" = 0 ]
