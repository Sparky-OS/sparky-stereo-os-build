#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/24
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the window program (usr/bin/droidcam) against server.py and v4l2-shim.c, in a container with its own virtual display (Xvfb).
# What the window shows after a stream ends is read from its button: references of "Stop" (streaming) and "Connect" (after the Stop button)
# are taken in the same session and each case's button is compared with them; the screenshots are kept for a person to look at.
# Runs as an unprivileged user in a container where /dev/video0 is a character device (run-gui.sh makes it).
# Usage: gui-cases.sh staged|first|fixed GUI OUTDIR     staged: 2.1.7-1, first: the first 2.1.7-2, fixed: the final one
set -uo pipefail
MODE=$1 GUI=$2 OUT=$3
HERE=$(cd "$(dirname "$0")" && pwd)
export HOME=/tmp/guihome DISPLAY=:99 NO_AT_BRIDGE=1 GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1
mkdir -p "$HOME/.config" "$OUT"
WORK=$(mktemp -d)
gcc -shared -fPIC -O2 -o "$WORK/shim.so" "$HERE/v4l2-shim.c" -ldl || exit 2
fail=0
port=24800
expect() { if [ "$3" = 1 ]; then echo "ok   $1: $2"; else echo "FAIL $1: $2"; fail=1; fi; }
BUTTON=168x34+279+82
crop() { import -window root -crop $BUTTON +repage "$1"; }
same() { [ "$(compare -fuzz 3% -metric AE "$1" "$2" null: 2>&1 | cut -d' ' -f1)" = 0 ]; }
state() {
	crop "$WORK/btn.png"
	if same "$WORK/btn.png" "$WORK/ref-stop.png"; then echo stop
	elif same "$WORK/btn.png" "$WORK/ref-connect.png"; then echo connect
	else echo other; fi
}
start_x() { Xvfb :99 -screen 0 800x500x24 > "$WORK/xvfb.log" 2>&1 & XPID=$!; sleep 2; }
stop_x() { kill $GPID $SPID 2>/dev/null; sleep 0.5; kill -9 $GPID 2>/dev/null; kill $XPID 2>/dev/null; wait 2>/dev/null; }
click_connect() { xdotool mousemove 363 98 click 1; sleep 0.3; xdotool mousemove 650 400; }
dialogs() { xdotool search --name '^Error$' 2>/dev/null | wc -l; }
launch() {   # name delay frames after
	port=$((port + 1))
	printf 'v4\nip=127.0.0.1\nport=%s\nvideo=1\naudio=0\n' $port > "$HOME/.config/droidcam"
	python3 "$HERE/server.py" $port "$2" "$3" "$4" > "$WORK/$1.server" 2>&1 & SPID=$!
	sleep 0.5
	env SHIM_COUNT_FILE="$WORK/$1.count" LD_PRELOAD="$WORK/shim.so" "$GUI" -dev=/dev/video0 > "$WORK/$1.out" 2> "$WORK/$1.err" & GPID=$!
	sleep 3
}
frames() { cat "$WORK/$1.count" 2>/dev/null || echo 0; }
# observe: name seconds -> sets DIALOG, STATE, FRAMES and keeps the screenshots (before and after dismissing a dialog)
observe() {
	sleep "$2"
	DIALOG=$(dialogs); FRAMES=$(frames "$1")
	import -window root "$OUT/$MODE-$1-1.png"
	if [ "$DIALOG" != 0 ]; then xdotool search --name '^Error$' | head -1 | xargs -I{} xdotool windowfocus {} 2>/dev/null; xdotool key Return; sleep 1.5; fi
	import -window root "$OUT/$MODE-$1-2.png"
	STATE=$(state)
	GUI_ALIVE=no; kill -0 $GPID 2>/dev/null && GUI_ALIVE=yes
	[ "$DIALOG" != 0 ] && DIALOG=yes || DIALOG=no
	echo "$MODE $1: dialog=$DIALOG, window after=$STATE, frames=$FRAMES, window program running=$GUI_ALIVE"
	montage "$OUT/$MODE-$1-1.png" "$OUT/$MODE-$1-2.png" -tile 2x1 -geometry 600x375+2+2 "$OUT/$MODE-$1-montage.png" 2>/dev/null
}

# references: a fast phone, Connect, then Stop (the button's own path)
start_x; launch ref 0.3 900 hold
crop "$WORK/ref-connect-idle.png"
click_connect; sleep 5; crop "$WORK/ref-stop.png"; import -window root "$OUT/$MODE-ref-streaming.png"
click_connect; sleep 2; crop "$WORK/ref-connect.png"
echo "references: streaming frames=$(frames ref), idle Connect crop equals the one after Stop: $(same "$WORK/ref-connect-idle.png" "$WORK/ref-connect.png" && echo yes || echo no)"
stop_x

# 1 the slow phone: first picture after 9 s
start_x; launch g1 9 900 hold; click_connect; observe g1 20; stop_x
if [ "$MODE" = staged ]; then
	expect g1 "RED: the window says Stop, no picture ever arrives, nothing is said" "$([ "$FRAMES$DIALOG$STATE" = "0nostop" ] && echo 1 || echo 0)"
else
	expect g1 "pictures arrive after the wait (more than 100 frames), no dialog, the window says Stop" "$([ "$FRAMES" -gt 100 ] && [ "$DIALOG$STATE" = nostop ] && echo 1 || echo 0)"
fi
# 2 the phone answers and never sends a picture
if [ "$MODE" = staged ]; then T2=20; else T2=68; fi
start_x; launch g2 1000 0 hold; click_connect; observe g2 $T2; stop_x
if [ "$MODE" = fixed ]; then
	expect g2 "a dialog says the phone sent no picture, and the window says Connect again" "$([ "$DIALOG$STATE" = yesconnect ] && echo 1 || echo 0)"
elif [ "$MODE" = first ]; then
	expect g2 "FIRST 2.1.7-2: a dialog, and the window stays on Stop" "$([ "$DIALOG$STATE" = yesstop ] && echo 1 || echo 0)"
else
	expect g2 "RED: nothing said, the window says Stop" "$([ "$DIALOG$STATE" = nostop ] && echo 1 || echo 0)"
fi
# 3 the stream is lost (30 frames, then the phone closes), and Connect again
start_x; launch g3 0.3 30 close; click_connect; observe g3 6
if [ "$MODE" = fixed ]; then
	expect g3 "a dialog says the connection was lost, and the window says Connect again" "$([ "$DIALOG$STATE" = yesconnect ] && echo 1 || echo 0)"
	kill $SPID 2>/dev/null; sleep 0.5
	python3 "$HERE/server.py" $port 0.3 900 hold > "$WORK/g3b.server" 2>&1 & SPID=$!
	sleep 0.5; before=$(frames g3); click_connect; sleep 5; after=$(frames g3); STATE=$(state); import -window root "$OUT/$MODE-g3-3-reconnected.png"
	echo "$MODE g3: Connect again: frames $before -> $after, window=$STATE"
	expect g3 "Connect works again without restarting the program (frames go on, the window says Stop)" "$([ "$((after - before))" -gt 30 ] && [ "$STATE" = stop ] && echo 1 || echo 0)"
elif [ "$MODE" = first ]; then
	expect g3 "FIRST 2.1.7-2: a dialog, and the window stays on Stop" "$([ "$DIALOG$STATE" = yesstop ] && echo 1 || echo 0)"
else
	expect g3 "RED: nothing said, the window says Stop" "$([ "$DIALOG$STATE" = nostop ] && echo 1 || echo 0)"
fi
stop_x
# 4 the stream stalls after 3 frames
if [ "$MODE" = fixed ]; then T4=22; else T4=20; fi
start_x; launch g4 0.3 3 hold; click_connect; observe g4 $T4; stop_x
if [ "$MODE" = fixed ]; then
	expect g4 "a dialog says the connection was lost, and the window says Connect again" "$([ "$DIALOG$STATE" = yesconnect ] && echo 1 || echo 0)"
elif [ "$MODE" = first ]; then
	expect g4 "FIRST 2.1.7-2: a dialog, and the window stays on Stop" "$([ "$DIALOG$STATE" = yesstop ] && echo 1 || echo 0)"
else
	expect g4 "RED: nothing said, the window says Stop" "$([ "$DIALOG$STATE" = nostop ] && echo 1 || echo 0)"
fi
# 5 the window program is stopped and continued while it receives
start_x; launch g5 0.3 900 hold; click_connect; sleep 3; a=$(frames g5)
kill -STOP $GPID; sleep 1; kill -CONT $GPID; sleep 3; b=$(frames g5); observe g5 8; c=$FRAMES; stop_x
echo "$MODE g5: frames before=$a, 3 s after the continue=$b, 11 s after=$c"
if [ "$MODE" = fixed ]; then
	expect g5 "frames go on after the continue, no dialog, the window says Stop" "$([ "$((c - b))" -gt 100 ] && [ "$DIALOG$STATE" = nostop ] && echo 1 || echo 0)"
else
	expect g5 "RED: no frame after the continue, nothing said, the window says Stop" "$([ "$((c - b))" -le 2 ] && [ "$DIALOG$STATE" = nostop ] && echo 1 || echo 0)"
fi
rm -rf "$WORK"
exit $fail
