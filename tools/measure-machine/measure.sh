#!/bin/bash
# Measures a machine's display stack for stereo work: kernel, GPU and its driver, connectors and their
# EDID 3D and deep-colour capabilities, KScreen outputs, EGL, GLX and Vulkan, KWin and the key packages.
# Run it on the machine as the session user; save its output to compare before and after a change.
# Read-only. Uses the running Plasma session's environment for the GL, Vulkan and KWin queries.
# Usage: measure.sh > machine-$(date +%F).txt
pid=$(pgrep -u "$USER" -x kwin_wayland | head -1)
if [ -n "$pid" ]; then
	for v in WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS DISPLAY; do
		val=$(tr '\0' '\n' < /proc/$pid/environ | sed -n "s/^$v=//p" | head -1); [ -n "$val" ] && export $v="$val"
	done
fi
s() { echo "===== $1"; }
s date; date -Is
s uname; uname -a
s os-release; cat /etc/os-release
s cmdline; cat /proc/cmdline
s lspci; lspci -nnk | grep -A3 -E 'VGA|Display|3D'
s modules; lsmod | grep -E '^(amdgpu|radeon|drm|snd_hda)' 
s mem; free -h
s disks; lsblk -o NAME,SIZE,MODEL,MOUNTPOINT
s connectors; for c in /sys/class/drm/card*-*; do echo "$(basename $c) $(cat $c/status 2>/dev/null) $(cat $c/enabled 2>/dev/null) modes: $(tr '\n' ' ' < $c/modes 2>/dev/null)"; done
s edid-decode; for c in /sys/class/drm/card*-HDMI-*; do [ -s $c/edid ] && { echo "--- $(basename $c)"; edid-decode < $c/edid 2>/dev/null | grep -i -E '3D|Deep Color|DC_|Vendor-Specific|VIC|stereo' | head -40 || echo "edid-decode not installed"; }; done
s kscreen-doctor; kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
s eglinfo; eglinfo -B 2>&1 | head -60
s glxinfo; glxinfo -B 2>&1 | head -40
s vulkaninfo; vulkaninfo --summary 2>&1 | head -60
s kwin-support; qdbus6 org.kde.KWin /KWin supportInformation 2>&1 | head -120
s key-packages; dpkg -l 'linux-image-*' 'libgl1-mesa-dri' 'mesa-vulkan-drivers' 'kwin-wayland' 'libqt6gui6' 'libkscreen*' 'plasma-workspace' 'firmware-amd-graphics' 'stereo-*' 'libstereo-*' 2>/dev/null | awk '/^ii/{print $2, $3}'
s dmesg-gpu; sudo -n dmesg 2>/dev/null | grep -i -E 'amdgpu|drm|hdmi' | tail -60
s sensors; sensors 2>/dev/null | head -30
s failed-units; systemctl is-system-running; systemctl --failed --no-legend --plain; systemctl --user --failed --no-legend --plain 2>/dev/null
