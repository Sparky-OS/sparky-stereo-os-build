#!/bin/bash
# frame-case.sh -- inside a part-A container (run-frame.sh starts it), as uid 1000, in a private session bus: one fresh
# Stereo KWin session (virtual output 1920x1080), /probe/frame-check (Qt's own frame, WAYLAND_DEBUG=client) and two drags
# with fake input through one served fakeinput connection, so the button stays down across captures:
#   the bottom-right corner of the frame by DRAG_STEPS moves of +60,+40, then released;
#   the left edge of the frame by DRAG_STEPS moves of -60,0, then released.
# A capture of the screen (both eyes when KWin has stereo content, one picture otherwise) and KWin's window list after
# every move and after each release: step-K.png, step-K.json, step-K.windows.json; the program's last paint line at that
# moment in step-K.paint. Results in /out.
set -u
OUT=/out
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/rt XDG_CONFIG_HOME=/tmp/home/.config
mkdir -p -m 700 "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_CONFIG_HOME"
printf '[StereoDepth]\nSunkLimit=10\nPoppedLimit=4\n' > "$XDG_CONFIG_HOME/kwinrc"
log() { printf '%s %s\n' "$(date -u +%H:%M:%S.%N | cut -c1-12)" "$*" >> "$OUT/case.log"; }
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
	kwin_wayland --virtual --socket=w --width 1920 --height 1080 > "$OUT/kwin.log" 2>&1 &
KPID=$!
for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/w" ] && break; sleep 0.2; done
[ -S "$XDG_RUNTIME_DIR/w" ] || { log "KWin did not start"; exit 1; }
export WAYLAND_DISPLAY=w QT_QPA_PLATFORM=wayland
sh /proofrig/build-fakeinput.sh /tmp/fi > /dev/null 2>&1 || { log "fakeinput did not build"; exit 1; }
WAYLAND_DEBUG=client /probe/frame-check > "$OUT/stdout.txt" 2> "$OUT/stderr.txt" &
APID=$!
sleep 6
k=0
cap() {
	python3 /proofrig/capture.py "$OUT/step-$k.png" > "$OUT/step-$k.json" 2>&1
	python3 /proofrig/kwin_windows.py "$OUT/kwin.log" > "$OUT/step-$k.windows.json" 2>&1
	grep '^FC paint' "$OUT/stderr.txt" | tail -1 > "$OUT/step-$k.paint"
	log "capture $k ($1): $(cat "$OUT/step-$k.paint")"
	k=$((k + 1))
}
cap start
mkfifo /tmp/fi.in /tmp/fi.ack
/tmp/fi/fakeinput --serve /tmp/fi.in /tmp/fi.ack >> "$OUT/fakeinput.log" 2>&1 &
FPID=$!
exec 7> /tmp/fi.in
exec 8< /tmp/fi.ack
send() { echo "$1" >&7; local a; read -r -t 15 a <&8; log "fakeinput '$1': ${a:-no answer}"; }
frame() { python3 -c 'import json,sys; w=[w for w in json.load(open(sys.argv[1]))["windows"] if w.get("caption")=="frame-check"]; print(*w[0]["fg"]) if w else print("")' "$1"; }
n=${DRAG_STEPS:-4}
read -r x y w h <<< "$(frame "$OUT/step-0.windows.json")"
[ -n "${x:-}" ] || { log "no frame-check window in KWin's list"; exit 1; }
# bottom-right corner, inside Qt's 3 px border
cx=$((x + w - 2)) cy=$((y + h - 2))
send "m:$cx,$cy"; sleep 0.5; send "p:272"; sleep 0.5
for i in $(seq 1 "$n"); do send "m:$((cx + 60 * i)),$((cy + 40 * i))"; sleep "${MOVE_WAIT:-0.8}"; cap "corner move $i, button down"; done
send "r:272"; sleep 1.5; cap "corner released"
read -r x y w h <<< "$(frame "$OUT/step-$((k - 1)).windows.json")"
ex=$((x + 1)) ey=$((y + h / 2))
send "m:$ex,$ey"; sleep 0.5; send "p:272"; sleep 0.5
for i in $(seq 1 "$n"); do send "m:$((ex - 60 * i)),$ey"; sleep "${MOVE_WAIT:-0.8}"; cap "left edge move $i, button down"; done
send "r:272"; sleep 1.5; cap "left edge released"
exec 7>&-
sleep 0.5; kill "$FPID" 2>/dev/null
touch "$OUT/done"
grep -o -E '/[^ ]*libQt6[A-Za-z]*[^ ]*' "/proc/$APID/maps" 2>/dev/null | sort -u > "$OUT/maps.txt"
log "program alive at the end: $(kill -0 "$APID" 2>/dev/null && echo yes || echo no)"
kill "$APID" 2>/dev/null; sleep 1; kill -9 "$APID" 2>/dev/null; wait "$APID" 2>/dev/null
kill "$KPID" 2>/dev/null; wait "$KPID" 2>/dev/null
exit 0
