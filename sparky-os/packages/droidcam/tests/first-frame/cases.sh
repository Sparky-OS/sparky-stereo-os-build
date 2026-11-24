#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/24
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: runs droidcam-cli against server.py (a stand-in for the DroidCam app) with v4l2-shim.c standing in for the video device.
# Inside a container with gcc and python3, no network needed. Usage: cases.sh staged|fixed CLIENT
# "staged" expects the failures of droidcam 2.1.7-1+lc1 (the red), "fixed" the behaviour of 2.1.7-2.
set -uo pipefail
MODE=$1 CLIENT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
gcc -shared -fPIC -O2 -o "$WORK/shim.so" "$HERE/v4l2-shim.c" -ldl || exit 2
fail=0
port=24747
case_run() {
	local name=$1 delay=$2 frames=$3 after=$4 limit=$5
	port=$((port + 1))
	python3 "$HERE/server.py" $port "$delay" "$frames" "$after" > "$WORK/$name.server" 2>&1 &
	local spid=$!
	sleep 0.5
	local t0=$(date +%s.%N)
	timeout -s INT "$limit" env SHIM_COUNT_FILE="$WORK/$name.count" SHIM_SIZE="${SIZE:-640x480}" LD_PRELOAD="$WORK/shim.so" "$CLIENT" -nocontrols -dev=/dev/null 127.0.0.1 $port > "$WORK/$name.out" 2> "$WORK/$name.err"
	echo $? > "$WORK/$name.rc"
	awk -v a="$(date +%s.%N)" -v b="$t0" 'BEGIN { printf "%.1f\n", a - b }' > "$WORK/$name.secs"
	kill $spid 2>/dev/null; wait $spid 2>/dev/null
	[ -f "$WORK/$name.count" ] || echo 0 > "$WORK/$name.count"
}
expect() {
	local name=$1 what=$2 ok=$3
	if [ "$ok" = 1 ]; then echo "ok   $name: $what"; else echo "FAIL $name: $what"; fail=1; fi
}
has() { grep -q -- "$2" "$WORK/$1.err" && echo 1 || echo 0; }
frames() { cat "$WORK/$1.count"; }
rc() { cat "$WORK/$1.rc"; }
ge() { [ "$(printf '%.0f' "$1")" -ge "$2" ] && echo 1 || echo 0; }
eq() { [ "$1" = "$2" ] && echo 1 || echo 0; }

# the app starts its camera 9 s after the request (the phone measured 7 to 16 s)
case_run slow 9 900 hold 25
echo "slow: frames=$(frames slow) rc=$(rc slow) secs=$(cat $WORK/slow.secs)"
if [ "$MODE" = fixed ]; then
	expect slow "frames reach the device after the 9 s wait" "$(ge "$(frames slow)" 30)"
	expect slow "it says it is waiting" "$(has slow "waiting for the phone's camera")"
	expect slow "a stop is not reported as a loss" "$(eq "$(has slow "was lost")$(has slow "sent no picture")" 00)"
else
	expect slow "RED: no frame reaches the device (the receive timeout ends the video thread)" "$(eq "$(frames slow)" 0)"
	expect slow "RED: nothing said" "$(eq "$(has slow waiting)$(has slow lost)$(has slow "no picture")" 000)"
	expect slow "RED: still running when stopped" "$(eq "$(rc slow)" 124)"
fi

# a fast phone: no waiting line, same frames
case_run fast 0.3 900 hold 8
echo "fast: frames=$(frames fast) rc=$(rc fast)"
expect fast "frames reach the device" "$(ge "$(frames fast)" 30)"
expect fast "no waiting line when the picture comes at once" "$(eq "$(has fast "waiting for the phone's camera")" 0)"

# the stream ends after 30 frames
case_run lost 0.3 30 close 20
echo "lost: frames=$(frames lost) rc=$(rc lost) secs=$(cat $WORK/lost.secs)"
if [ "$MODE" = fixed ]; then
	expect lost "exit status 4" "$(eq "$(rc lost)" 4)"
	expect lost "it says the connection was lost" "$(has lost "The connection to the phone was lost")"
else
	expect lost "RED: still running, nothing said" "$(eq "$(rc lost)$(has lost lost)" 1240)"
fi

# the phone sends 5 frames, is silent for 8 s, and again (gaps of 5 s and more between bursts were seen on the phone; the staged client gives up after about 6 s): a live stream
case_run burst 0.3 5 bursts 28
echo "burst: frames=$(frames burst) rc=$(rc burst)"
if [ "$MODE" = fixed ]; then
	expect burst "the stream lives through the gaps (at least 15 frames in 28 s)" "$(ge "$(frames burst)" 15)"
	expect burst "no loss reported" "$(eq "$(has burst "was lost")" 0)"
else
	expect burst "RED: the timeout ends it after the first burst, nothing said" "$(eq "$(frames burst)$(has burst lost)$(rc burst)" 50124)"
fi

# the phone sends 3 frames and then nothing at all
case_run stall 0.3 3 hold 30
echo "stall: frames=$(frames stall) rc=$(rc stall) secs=$(cat $WORK/stall.secs)"
if [ "$MODE" = fixed ]; then
	expect stall "exit status 4 after about 15 s" "$(eq "$(rc stall)" 4)"
	expect stall "it says the connection was lost" "$(has stall "The connection to the phone was lost")"
	expect stall "not before 14 s" "$(ge "$(cat $WORK/stall.secs)" 14)"
else
	expect stall "RED: still running, nothing said" "$(eq "$(rc stall)$(has stall lost)" 1240)"
fi

# the app answers and never sends a picture
if [ "$MODE" = fixed ]; then limit=75; else limit=15; fi
case_run none 1000 0 hold $limit
echo "none: frames=$(frames none) rc=$(rc none) secs=$(cat $WORK/none.secs)"
if [ "$MODE" = fixed ]; then
	expect none "exit status 3" "$(eq "$(rc none)" 3)"
	expect none "it says the phone sent no picture" "$(has none "The phone sent no picture")"
	expect none "after about 60 s" "$(ge "$(cat $WORK/none.secs)" 59)"
else
	expect none "RED: still running, nothing said" "$(eq "$(rc none)$(has none "no picture")" 1240)"
fi

# the app closes the connection at once
case_run reset 0 0 reset 12
echo "reset: rc=$(rc reset)"
expect reset "it says the connection was reset" "$(has reset "Connection reset")"
if [ "$MODE" = fixed ]; then expect reset "exit status 1" "$(eq "$(rc reset)" 1)"; else expect reset "RED: still running" "$(eq "$(rc reset)" 124)"; fi

# the client is stopped and continued (Ctrl+Z, fg): recv() with a receive timeout returns EINTR after SIGCONT; read at every frame by the shim
stopcont() {
	local name=$1 delay=$2 stop=$3
	port=$((port + 1))
	python3 "$HERE/server.py" $port "$delay" 900 hold > "$WORK/$name.server" 2>&1 &
	local spid=$!
	sleep 0.5
	env SHIM_COUNT_FILE="$WORK/$name.count" LD_PRELOAD="$WORK/shim.so" "$CLIENT" -nocontrols -dev=/dev/null 127.0.0.1 $port > "$WORK/$name.out" 2> "$WORK/$name.err" &
	local cpid=$!
	sleep 3
	SC_A=$(cat "$WORK/$name.count" 2>/dev/null || echo 0)
	if [ "$stop" = yes ]; then kill -STOP $cpid; sleep 1; kill -CONT $cpid; else sleep 1; fi
	sleep 3
	SC_B=$(cat "$WORK/$name.count" 2>/dev/null || echo 0)
	sleep 12
	SC_C=$(cat "$WORK/$name.count" 2>/dev/null || echo 0)
	SC_ALIVE=no; kill -0 $cpid 2>/dev/null && SC_ALIVE=yes
	kill -INT $cpid 2>/dev/null; sleep 1; kill -KILL $cpid 2>/dev/null; kill $spid 2>/dev/null; wait 2>/dev/null
	echo "$name (stopped and continued: $stop): frames before=$SC_A, 3 s after=$SC_B, 15 s after=$SC_C, running at the end=$SC_ALIVE"
}
stopcont sc-stream-control 0.3 no
expect sc-stream-control "control, no stop: frames go on (more than 100 between 3 s and 15 s after)" "$(ge $((SC_C - SC_B)) 100)"
stopcont sc-stream 0.3 yes
if [ "$MODE" = fixed ]; then
	expect sc-stream "in a stream: frames go on after the continue" "$(ge $((SC_C - SC_B)) 100)"
	expect sc-stream "nothing false is said" "$(eq "$(has sc-stream "was lost")$(has sc-stream "sent no picture")" 00)"
else
	expect sc-stream "RED: after the continue no frame arrives, nothing is said, the client still runs" "$(eq "$((SC_C - SC_B))$(has sc-stream lost)$(has sc-stream "no picture")$SC_ALIVE" 000yes)"
fi
stopcont sc-firstwait-control 4 no
expect sc-firstwait-control "control, no stop: the first frame at 4 s, frames go on" "$(ge "$SC_C" 100)"
stopcont sc-firstwait 4 yes
if [ "$MODE" = fixed ]; then
	expect sc-firstwait "in the first-frame wait: the picture comes after the continue" "$(ge "$SC_C" 100)"
	expect sc-firstwait "nothing false is said" "$(eq "$(has sc-firstwait "was lost")$(has sc-firstwait "sent no picture")" 00)"
else
	expect sc-firstwait "RED: no frame ever, still running" "$(eq "$SC_C$SC_ALIVE" 0yes)"
fi

# a frame cut in two by a pause of 8 s (a stop, a stall): whole or failed, never short
case_run cut 0.3 5 cut:8 20
echo "cut: frames=$(frames cut) rc=$(rc cut)"
if [ "$MODE" = fixed ]; then
	expect cut "the pictures arrive whole (5, the cut one, 20: at least 24, the client skips a frame when it is busy) and nothing is said about the stream" "$([ "$(frames cut)" -ge 24 ] && [ "$(has cut 'cannot be right')$(has cut 'tjDecompress')$(has cut 'was lost')" = 000 ] && echo 1 || echo 0)"
else
	expect cut "RED: a short count taken for a whole frame puts the stream out of step (about 6 pictures instead of 25, or errors)" "$(eq "$([ "$(frames cut)" -lt 24 ] || [ -s $WORK/cut.err ] && echo 1)" 1)"
fi
# a frame cut and then silence for ever
case_run cutstall 0.3 5 cutstall 40
echo "cutstall: frames=$(frames cutstall) rc=$(rc cutstall) secs=$(cat $WORK/cutstall.secs)"
if [ "$MODE" = fixed ]; then
	expect cutstall "5 whole pictures, exit 4, the connection was lost, after about 15 s" "$(eq "$(frames cutstall)$(rc cutstall)$(has cutstall 'was lost')" 541)"
else
	expect cutstall "RED: nothing said, still running" "$(eq "$(rc cutstall)$(has cutstall 'was lost')" 1240)"
fi
# the phone sends 640x480 and the device takes 1280x720
SIZE=1280x720 case_run scaled 0.3 900 hold 8
echo "scaled: frames=$(frames scaled)"
expect scaled "frames reach the 1280x720 device" "$(ge "$(frames scaled)" 30)"
if [ "$MODE" = fixed ]; then
	expect scaled "the client says once which size the phone sends and which it is shown at" "$(eq "$(grep -c 'the phone sends 640x480, shown at 1280x720' "$WORK/scaled.err")" 1)"
else
	expect scaled "RED: nothing said about the scaling" "$(eq "$(has scaled 'shown at')" 0)"
fi
case_run unscaled 0.3 900 hold 6
expect unscaled "no scaling line when the sizes agree" "$(eq "$(has unscaled 'shown at')" 0)"

rm -rf "$WORK"
exit $fail
