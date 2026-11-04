#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-3 (U41): stereo-display-info says when a probe could not run, timed out or failed, apart from the real answer "not
# announced"; the normal answers are unchanged. Fake probe tools in a private PATH; the script reads the real /sys (no card needed).
# Usage: probe-proof.sh STEREO_DISPLAY_INFO      exit 0 only when every case matches
set -u
S=${1:?the stereo-display-info script}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/core"
for t in sh sleep sed awk timeout mktemp head cut cat rm md5sum basename readlink uname wc tr grep; do
	p=$(command -v "$t") && ln -s "$p" "$T/core/$t"
done
fails=0
ok() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
fake() { printf '#!/bin/sh\n%s\n' "$2" >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
reset() { rm -f "$T"/bin/*; fake edid-decode 'exit 0'; }
info() { # info [ENV=VALUE...]: the report in $T/out
	env -i PATH="$T/bin:$T/core" "$@" sh "$S" ${MODE:---sections} >"$T/out" 2>"$T/err"; status=$?
}
has() { grep -qF -- "$1" "$T/out"; }
notann() { grep "Compositor stereo" "$T/out" | grep -qF "not announced"; }
WL=WAYLAND_DISPLAY=wayland-0

echo "== the compositor probe, Wayland"
reset
fake wayland-info "echo \"interface: 'kde_stereo_content_manager_v1', version: 2, name: 31\""
info $WL
has "Compositor stereo: announced (kde_stereo_content_manager_v1, version 2)"; ok $? "announced: said as before"
fake wayland-info "echo \"interface: 'wl_compositor', version: 6, name: 1\""
info $WL
has "Compositor stereo: not announced"; ok $? "answer without the interface: not announced"
fake wayland-info 'echo "failed to connect to display" >&2; exit 3'
info $WL
has "Compositor stereo: could not be checked (wayland-info exited with status 3 (failed to connect to display))" && ! notann; ok $? "wayland-info fails: the failure and its reason, not 'not announced' ($(grep 'Compositor' "$T/out"))"
fake wayland-info 'sleep 30'
info $WL
has "Compositor stereo: could not be checked (wayland-info did not answer within 10 seconds)" && ! notann; ok $? "wayland-info times out: said ($(grep 'Compositor' "$T/out"))"
reset
info $WL
has "Compositor stereo: could not be checked (wayland-info is not installed)"; ok $? "wayland-info missing: said"
echo "== X11"
fake xprop 'echo "_KDE_NET_WM_STEREO_CONTENT_SUPPORTED:  not found."'
info DISPLAY=:0
has "Compositor stereo: not announced"; ok $? "xprop answers not found: not announced"
fake xprop 'echo "_KDE_NET_WM_STEREO_CONTENT_SUPPORTED(CARDINAL) = 1"'
info DISPLAY=:0
has "Compositor stereo: announced (_KDE_NET_WM_STEREO_CONTENT_SUPPORTED, version 1)"; ok $? "xprop announces: said as before"
fake xprop 'echo "xprop: unable to open display :0" >&2; exit 1'
info DISPLAY=:0
has "Compositor stereo: could not be checked (xprop exited with status 1 (xprop: unable to open display :0))" && ! notann; ok $? "xprop fails: said"
rm -f "$T/bin/xprop"
info DISPLAY=:0
has "Compositor stereo: could not be checked (xprop is not installed)"; ok $? "xprop missing: said"
echo "== no session"
reset
info
! has "Compositor stereo" && ! has "kscreen-doctor"; ok $? "no desktop session (SSH, console): no compositor line, no kscreen note"
echo "== the live display state"
reset
info $WL
has "Live display state, not read: kscreen-doctor is not installed"; ok $? "kscreen-doctor missing in a session: said"
fake kscreen-doctor 'echo "cannot connect to the compositor" >&2; exit 1'
info $WL
has "Live display state, not read: kscreen-doctor -o exited with status 1 (cannot connect to the compositor)"; ok $? "kscreen-doctor fails: said"
fake kscreen-doctor 'sleep 30'
info $WL
has "Live display state, not read: kscreen-doctor -o did not answer within 10 seconds"; ok $? "kscreen-doctor times out: said"
fake kscreen-doctor 'if [ "$1" = -j ]; then echo broken >&2; exit 4; fi; printf "Output: 1 HDMI-A-1 enabled connected\n"'
info $WL
has "Stereo and HDR switches of the displays, not read: kscreen-doctor -j exited with status 4 (broken)"; ok $? "kscreen-doctor -j fails after -o worked: said"
fake kscreen-doctor 'if [ "$1" = -j ]; then echo "{}"; exit 0; fi; printf "Output: 1 HDMI-A-1 enabled connected\n"'
info $WL
! has "not read: kscreen-doctor"; ok $? "kscreen-doctor works: no note"
echo "== OpenGL and Vulkan"
reset
info
has "OpenGL renderer of each card, not read: eglinfo is not installed" && has "Vulkan device of each card, not read: vulkaninfo is not installed"; ok $? "eglinfo and vulkaninfo missing: said"
fake eglinfo 'echo "eglinfo: no display" >&2; exit 1'
fake vulkaninfo 'echo "ERROR_INITIALIZATION_FAILED" >&2; exit 2'
info
has "OpenGL renderer of each card, not read completely: eglinfo exited with status 1 (eglinfo: no display)" && has "Vulkan device of each card, not read: vulkaninfo exited with status 2 (ERROR_INITIALIZATION_FAILED)"; ok $? "both fail: said with their reasons"
fake eglinfo 'echo "Device platform:"'
fake vulkaninfo 'echo "Devices:"'
info
! has "not read"; ok $? "both work: no note"
echo "== unchanged"
MODE=--keys info
[ "$status" = 0 ] && ! has "not read" && ! has "Compositor"; ok $? "--keys prints no probe notes (the page parses it)"
fake edid-decode 'exit 0'; rm -f "$T/bin/edid-decode"
info $WL
[ "$(cat "$T/out")" = "edid-decode is not installed." ] && [ "$status" = 0 ]; ok $? "edid-decode missing: its own message, unchanged"
echo "failures: $fails"
[ "$fails" = 0 ]
