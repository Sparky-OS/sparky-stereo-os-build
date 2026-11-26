#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# case.sh CASE -- inside a rig container (run.sh starts it), as uid 1000: one fresh Stereo KWin session on a virtual
# output 1920x1080, in its side-by-side 3D twin unless the case is 2D, the person's limits written as System Settings
# writes them (kwinrc [StereoDepth]: SunkLimit 10, PoppedLimit 4, ElementLimit from ELEMENT, 1 by default), one program,
# then both eyes captured with KWin's ScreenShot2 and KWin's own list of windows. Results in /out/CASE.
#   CASE  okular-3d okular-scrolled okular-presentation okular-background okular-2d
#         preview-3d preview-scrolled preview-background preview-2d
#   ELEMENT  the element limit (pixels of a view 1920 wide); 0 lays the elements flat, 12 is a measuring scale
set -u
CASE=$1
ELEMENT=${ELEMENT:-1}
OUT=/out/$CASE
mkdir -p "$OUT"
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/rt XDG_CONFIG_HOME=/tmp/home/.config XDG_DATA_HOME=/tmp/home/.local/share
export XDG_CACHE_HOME=/tmp/home/.cache XDG_STATE_HOME=/tmp/home/.local/state LANG=C.UTF-8
mkdir -p -m 700 "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/okular/docdata" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
printf '[StereoDepth]\nSunkLimit=10\nPoppedLimit=4\nElementLimit=%s\n' "$ELEMENT" > "$XDG_CONFIG_HOME/kwinrc"
printf '[KDE]\nAnimationDurationFactor=0\nCursorBlinkRate=0\n' > "$XDG_CONFIG_HOME/kdeglobals"
printf '[Daemon]\nAutolock=false\nLockOnResume=false\nTimeout=0\n' > "$XDG_CONFIG_HOME/kscreenlockerrc"
# Okular: a desk of one colour key (magenta), no messages over the view, the sidebar closed; 100 % for the two pages in
# view, fit width for the page run under the toolbar
zoom=0; [ "$CASE" = okular-scrolled ] && zoom=1
printf '[General]\nUseCustomBackgroundColor=true\nBackgroundColor=255,0,255\nShowOSD=false\nShowSidebar=false\n[Zoom]\nZoomMode=%s\n[Core General]\nContinueFromLastViewedPage=true\n' \
    "$zoom" > "$XDG_CONFIG_HOME/okularpartrc"
printf '[General]\nShowSidebar=false\nShowBottomBar=false\n' > "$XDG_CONFIG_HOME/okularrc"
pdf=/tmp/two-pages.pdf
python3 -I /tests/make-pdf.py "$pdf" 300 200
if [ "$CASE" = okular-scrolled ]; then
	# the document opens scrolled: the top of the view a third of the way down the first page
	size=$(stat -c %s "$pdf")
	printf '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE documentInfo>\n<documentInfo url="%s">\n <generalInfo>\n  <history>\n   <current viewport="0;C2:0.5:0.35:2"/>\n  </history>\n </generalInfo>\n</documentInfo>\n' \
		"$pdf" > "$XDG_DATA_HOME/okular/docdata/$size.two-pages.pdf.xml"
fi
cat > /tmp/session.sh <<'SESSION'
set -u
OUT=$1 CASE=$2
export KWIN_VIRTUAL_STEREO_MODES=1
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
	kwin_wayland --virtual --socket=sub --width 1920 --height 1080 > "$OUT/kwin.log" 2>&1 &
kwin=$!
for i in $(seq 100); do [ -S "$XDG_RUNTIME_DIR/sub" ] && break; sleep 0.1; done
[ -S "$XDG_RUNTIME_DIR/sub" ] || { echo "KWin did not start" > "$OUT/result.txt"; exit 1; }
sleep 1
kd() { WAYLAND_DISPLAY=sub kscreen-doctor "$@"; }
o=$(kd -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/{print $3; exit}')
if [ "${CASE##*-}" != 2d ]; then
	m=$(kd -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -o '[0-9]*:1920x1080@60[^ ]*' | grep -i -m1 '3D-SBS' | cut -d: -f1)
	kd "output.$o.mode.$m" > "$OUT/mode.txt" 2>&1; sleep 1
fi
kd -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' > "$OUT/outputs.txt"
env=(WAYLAND_DISPLAY=sub QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
	__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json)
place() { python3 -I /tests/kwin_script.py "$OUT/kwin.log" "$1"; sleep 1.5; }
case $CASE in
okular-presentation)
	env "${env[@]}" WAYLAND_DEBUG=client okular --presentation /tmp/two-pages.pdf > "$OUT/program.out" 2> "$OUT/program.err" & prog=$!
	sleep 9 ;;
okular-*)
	env "${env[@]}" WAYLAND_DEBUG=client okular /tmp/two-pages.pdf > "$OUT/program.out" 2> "$OUT/program.err" & prog=$!
	sleep 8
	place 'var w = workspace.activeWindow; w.setMaximize(false, false); w.frameGeometry = {x: 60, y: 40, width: 1500, height: 960};'
	sleep 2 ;;
preview-*)
	mode=all; [ "$CASE" = preview-scrolled ] && mode=single
	env "${env[@]}" WAYLAND_DEBUG=client /out/bin/preview "$mode" 2.5 0.35 > "$OUT/program.out" 2> "$OUT/program.err" & prog=$!
	sleep 6
	place 'var w = workspace.activeWindow; w.setMaximize(false, false); w.frameGeometry = {x: 60, y: 40, width: 1500, height: 960};'
	sleep 2 ;;
esac
if [ "${CASE##*-}" = background ]; then
	# another window comes over the right of the screen and takes the focus: the program lies behind it
	env "${env[@]}" /out/bin/preview all > "$OUT/other.out" 2> "$OUT/other.err" & other=$!
	sleep 5
	place 'var ws = workspace.stackingOrder; var w = workspace.activeWindow; w.setMaximize(false, false); w.frameGeometry = {x: 1380, y: 300, width: 500, height: 600};'
	sleep 2
fi
python3 -I /tests/kwin_windows.py "$OUT/kwin.log" > "$OUT/windows.json" 2> "$OUT/windows.err"
python3 -I /tests/capture.py "$OUT/shot.png" > "$OUT/capture.json" 2> "$OUT/capture.err"
kill "$prog" 2>/dev/null; wait "$prog" 2>/dev/null
[ -n "${other:-}" ] && { kill "$other" 2>/dev/null; wait "$other" 2>/dev/null; }
kill "$kwin" 2>/dev/null; wait "$kwin" 2>/dev/null
grep -a -E 'kde_stereo|element_limit|depth_state|set_desktop_depth|set_content|get_depth' "$OUT/program.err" > "$OUT/wire.txt" 2>/dev/null
echo "done" > "$OUT/result.txt"
SESSION
exec dbus-run-session -- bash /tmp/session.sh "$OUT" "$CASE"
