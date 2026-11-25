#!/bin/bash
# case.sh KIND MODE STEPS WAIT -- inside a test container (run.sh starts it), as uid 1000: one fresh Stereo KWin session
# (virtual output 1920x1080, the person's limits 10 and 4) in a private session bus, then stereo-widget-move on Qt's
# Wayland platform, drawing with Mesa's software renderer (no GPU driver in the measured process).
#   KIND memcheck: under Valgrind's memcheck (--undef-value-errors=no, every error kept)
#   KIND lag:      with WAYLAND_DEBUG=client, then lag.py over the wire log
# LIBDIR (optional): a folder whose libraries come first (LD_LIBRARY_PATH), for a development build's libQt6Widgets.so.6
# and libQt6WaylandClient.so.6. OUTPUT_SCALE (optional, 1.25 or 1.5): the output's scale, set as Display Settings sets
# it, by kscreen-doctor in a setup KWin before the case's own (row 50's second round; the image needs libkscreen-bin).
# Results in /out/KIND-MODE.
set -u
KIND=$1 MODE=$2 STEPS=$3 WAIT=$4
OUT=/out/$KIND-$MODE
mkdir -p "$OUT"
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/rt XDG_CONFIG_HOME=/tmp/home/.config
mkdir -p -m 700 "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_CONFIG_HOME"
printf '[StereoDepth]\nSunkLimit=10\nPoppedLimit=4\n' > "$XDG_CONFIG_HOME/kwinrc"
printf '[Daemon]\nAutolock=false\nLockOnResume=false\nTimeout=0\n' > "$XDG_CONFIG_HOME/kscreenlockerrc"
if [ -n "${OUTPUT_SCALE:-}" ]; then
	kwin_wayland --virtual --socket=setup --width 1920 --height 1080 > "$OUT/setup-kwin.log" 2>&1 &
	SPID=$!
	for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/setup" ] && break; sleep 0.1; done; sleep 1.5
	WAYLAND_DISPLAY=setup kscreen-doctor "output.Virtual-0.scale.$OUTPUT_SCALE" > "$OUT/setup-scale.txt" 2>&1; sleep 1.5
	WAYLAND_DISPLAY=setup kscreen-doctor -o 2>/dev/null | sed "s/\x1b\[[0-9;]*m//g" >> "$OUT/setup-scale.txt"
	kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null; rm -f "$XDG_RUNTIME_DIR"/setup*
fi
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
	kwin_wayland --virtual --socket=w --width 1920 --height 1080 > "$OUT/kwin.log" 2>&1 &
KPID=$!
for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/w" ] && break; sleep 0.2; done
[ -S "$XDG_RUNTIME_DIR/w" ] || { echo "KWin did not start" > "$OUT/result.txt"; exit 1; }
sleep 2
env=(WAYLAND_DISPLAY=w QT_QPA_PLATFORM=wayland LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
	__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json)
[ -n "${LIBDIR:-}" ] && env+=(LD_LIBRARY_PATH="$LIBDIR")
prog=(/out/bin/stereo-widget-move "$MODE" "$STEPS" "$WAIT")
start=$(date +%s.%N)
if [ "$KIND" = memcheck ]; then
	env "${env[@]}" valgrind --tool=memcheck --log-file="$OUT/memcheck.txt" --num-callers=40 --undef-value-errors=no \
		--error-limit=no "${prog[@]}" > "$OUT/stdout.txt" 2> "$OUT/stderr.txt"
	rc=$?
else
	env "${env[@]}" WAYLAND_DEBUG=client "${prog[@]}" > "$OUT/stdout.txt" 2> "$OUT/stderr.txt"
	rc=$?
	python3 -I /tests/lag.py "$OUT/stderr.txt" "$OUT/lag.json" > /dev/null 2>&1 || echo '{"error": "lag.py failed"}' > "$OUT/lag.json"
fi
end=$(date +%s.%N)
printf 'rc=%s seconds=%s\n' "$rc" "$(echo "$end - $start" | bc)" > "$OUT/result.txt"
grep -a '^R863 result' "$OUT/stderr.txt" >> "$OUT/result.txt"
if [ -n "${LIBDIR:-}" ]; then
	# which Qt libraries the program really loaded
	env "${env[@]}" ldd /out/bin/stereo-widget-move | grep -E 'libQt6(Widgets|WaylandClient|Gui)' >> "$OUT/result.txt"
fi
kill "$KPID" 2>/dev/null; wait "$KPID" 2>/dev/null
exit 0
