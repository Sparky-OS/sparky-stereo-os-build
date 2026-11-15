#!/bin/sh
# The page's engine against the rig: a PipeWire and WirePlumber of their own, virtual cameras (PipeWire Video/Source nodes carrying
# api.v4l2.path) and a user-space V4L2 device behind /dev/videoN (rig/vcam-shim.c). Each row prints PASS or FAIL and the value read.
# Usage (inside the rig container, session started, cameras a, b and sbs up):  sh tests/rig-proof.sh ROW...   (rows: default persist modes controls two held norefuse replug)
. /var/tmp/camera-settings-page-570/work/env-rig.sh
unset LD_PRELOAD
CLI() { LD_PRELOAD=$VCAM_ROOT/vcam-shim.so sparky-stereo-camera "$@"; }
fails=0
check() { # check NAME CONDITION-RESULT(0 = true) DETAIL
	if [ "$2" = 0 ]; then echo "PASS $1: $3"; else echo "FAIL $1: $3"; fails=$((fails+1)); fi
}
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
resetcfg() { for n in 20 21 22 23; do cp /K3D/partners/queue/camera-settings-page-570/rig/vcam/video$n.cfg $VCAM_ROOT/ ; rm -f $VCAM_ROOT/video$n.state; done; rm -rf "$XDG_CONFIG_HOME/sparky-stereo-camera"; }
for row in "$@"; do
case $row in
default)
	CLI default cam-a; v=$(pw-metadata -n default 0 2>/dev/null | grep -E "default\.(configured\.)?video\.source" | sed "s/.*key:'\([^']*\)' value:'\([^']*\)'.*/\1=\2/" | tr '\n' ' ')
	echo "$v" | grep -q 'default.configured.video.source={ "name": "cam-a" }\|default.configured.video.source={"name":"cam-a"}'; check default-set-configured $? "$v"
	echo "$v" | grep -q 'default.video.source=.*cam-a'; check default-moved $? "WirePlumber moved default.video.source"
	for c in cam-a cam-sbs cam-b; do
		CLI default $c; sleep 1
		timeout 8 gst-launch-1.0 pipewiresrc stream-properties="props,media.type=Video,media.category=Capture,media.role=Camera" ! fakesink >/dev/null 2>&1 & p=$!; sleep 4
		got=$(python3 /K3D/partners/queue/camera-settings-page-570/rig/who-is-linked.py); kill $p 2>/dev/null
		echo "$got" | grep -q "camera=$c "; check default-followed-by-client-$c $? "$got"
	done ;;
persist)
	CLI default cam-a; sleep 5
	grep -q '^default.configured.video.source=cam-a' "$XDG_STATE_HOME/wireplumber/default-nodes"; check default-in-wireplumber-state $? "$(cat $XDG_STATE_HOME/wireplumber/default-nodes | tr '\n' ' ')"
	kill $(pidof wireplumber); sleep 1; nohup wireplumber >$XDG_RUNTIME_DIR/wireplumber.log 2>&1 & sleep 5
	[ "$(CLI default)" = cam-a ]; check default-after-wireplumber-restart $? "$(CLI default)" ;;
modes)
	f=$(CLI formats cam-a | jget "[ (x['format'], [ (s['width'],s['height'],s['rates']) for s in x['sizes']]) for x in d]")
	echo "$f" | grep -q "MJPG" && echo "$f" | grep -q "1920, 1080, \[30, 60\]"; check formats-listed-all $? "$f"
	CLI mode cam-a MJPG 1280x720 60; m=$(CLI mode cam-a | jget "d['format'],d['width'],d['height'],d['fps']")
	[ "$m" = "MJPG 1280 720 60" ]; check mode-set-and-read-back $? "$m"
	CLI mode cam-a YUYV 1280x720 99 2>/dev/null; [ $? != 0 ]; check mode-refused-says-so $? "exit status not 0"
	m2=$(CLI mode cam-a | jget "d['format'],d['width'],d['height'],d['fps']"); [ "$m2" = "$m" ]; check mode-refusal-keeps-earlier $? "$m2" ;;
controls)
	for spec in "brightness 77 integer" "contrast 5 integer" "auto_exposure 1 menu" "white_balance_automatic 0 boolean"; do set -- $spec
		CLI control cam-a $1 $2; r=$(CLI control cam-a $1 | jget "d['value'],d['kind']"); [ "$r" = "$2 $3" ]; check "control-$3-$1" $? "read back $r"
	done
	CLI control cam-a focus_reset 1; check control-button $? "button pressed, exit $?"
	out=$(CLI control cam-a sharpness 5 2>&1); [ $? != 0 ] && echo "$out" | grep -q "does not accept"; check control-refused-says-so $? "$out"
	out=$(CLI control cam-a exposure_time_absolute 100 2>&1); [ $? != 0 ] && echo "$out" | grep -q "does not allow"; check control-inactive-says-so $? "$out"
	out=$(CLI control cam-a brightness 999 2>&1); [ $? != 0 ]; check control-out-of-range-refused $? "$out"
	CLI reset cam-a; r=$(CLI control cam-a brightness | jget "d['value']"); [ "$r" = 128 ]; check reset-to-defaults $? "brightness $r (driver default 128)" ;;
two)
	CLI control cam-a brightness 33; a=$(CLI control cam-a brightness | jget "d['value']"); b=$(CLI control cam-b brightness | jget "d['value']"); n=$(CLI list | jget "len(d)")
	[ "$n" -ge 2 ] && [ "$a" = 33 ] && [ "$b" = 0 ]; check two-cameras-independent $? "cameras=$n cam-a=$a cam-b=$b" ;;
held)
	out=$(CLI mode cam-held YUYV 320x240 30 2>&1); [ $? != 0 ] && echo "$out" | grep -q "Another program is using"; check held-camera-says-so $? "$out"
	out=$(CLI control cam-held brightness 10 2>&1); [ $? = 0 ]; check held-camera-control-still-works $? "control set while the stream is held (UVC allows it)" ;;
replug)
	CLI control cam-a brightness 200; CLI mode cam-a MJPG 1280x720 60
	# unplug: the camera and its values go; plug in: it starts at its defaults
	rm -f $VCAM_ROOT/video20.cfg $VCAM_ROOT/video20.state
	out=$(CLI control cam-a brightness 2>&1); echo "$out" | grep -q "not connected"; check unplugged-says-so $? "$out"
	cp /K3D/partners/queue/camera-settings-page-570/rig/vcam/video20.cfg $VCAM_ROOT/
	r=$(CLI control cam-a brightness | jget "d['value']"); [ "$r" = 128 ]; check replugged-camera-is-at-defaults $? "brightness $r"
	LD_PRELOAD=$VCAM_ROOT/vcam-shim.so timeout 6 sparky-stereo-camera watch >$XDG_RUNTIME_DIR/watch.log 2>&1; r=$(CLI control cam-a brightness | jget "d['value']"); m=$(CLI mode cam-a | jget "d['format'],d['width'],d['height'],d['fps']")
	[ "$r" = 200 ] && [ "$m" = "MJPG 1280 720 60" ]; check watch-applied-saved-choice-at-plug-in $? "brightness $r, mode $m; $(tr '\n' ' ' < $XDG_RUNTIME_DIR/watch.log | cut -c1-160)" ;;
esac
done
[ $fails = 0 ] && echo "ALL PASS" || { echo "$fails FAILED"; exit 1; }
