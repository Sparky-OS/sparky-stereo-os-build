#!/bin/bash
# prog-case.sh -- inside a part-A container (run-prog.sh starts it), as uid 1000, in a private session bus: one fresh
# Stereo KWin session (virtual output 1920x1080, the person's limits 10 and 4, Xwayland), the program with
# WAYLAND_DEBUG=client, and a capture of both eyes (KWin's ScreenShot2) with KWin's window list at the start and after each
# step. Results in /out.
# Environment:
#   PROG        the program's command line
#   PROGENV     KEY=VALUE words for the program only
#   PRESETUP    a shell line run first (the program's settings files)
#   PROBE=1     the r863 probe is preloaded (Qt 6 Widgets programs; PROBE_LIB=r863-probe-qt5.so for a Qt 5 one): it
#               drives R863_STEPS, says when to capture (step-K.ready) and waits for step-K.captured
#   EXT_STEPS   without the probe: steps run from here, separated by '^': "kwin:JS" (KWin scripting), "fi:STEPS"
#               (KWin's fake input, the rig's fakeinput tool), "sleep:SECONDS"; a capture after each
#   SHIM        a second test aid in the probe's folder, preloaded after the probe (gl-shim.so, kubrick-shim-r863.so);
#               with GEOM_FILE set, the file it writes is copied beside each capture as step-K.geom.txt
#   OUTPUT_MODE 3d: the virtual output in its side-by-side 3D twin mode (a program that draws two eyes only on a screen
#               that shows them, as the stereo layer's StereoPicture does); OUTPUT_SCALE: the output's scale. Both are
#               set as Display Settings sets them, in a setup KWin before the case's own (stereo-proof-rig's login rig):
#               kscreen-doctor, the saved kwinoutputconfig.json, otherStereoFormats on for a 3D twin
#   CASE_TIMEOUT seconds for the whole program run (default 240)
set -u
OUT=/out
mkdir -p "$OUT"
export HOME=/tmp/home XDG_RUNTIME_DIR=/tmp/rt XDG_CONFIG_HOME=/tmp/home/.config XDG_DATA_HOME=/tmp/home/.local/share
mkdir -p -m 700 "$XDG_RUNTIME_DIR"; mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
printf '[StereoDepth]\nSunkLimit=10\nPoppedLimit=4\n' > "$XDG_CONFIG_HOME/kwinrc"
printf '[Daemon]\nAutolock=false\nLockOnResume=false\nTimeout=0\n' > "$XDG_CONFIG_HOME/kscreenlockerrc"
log() { printf '%s %s\n' "$(date -u +%H:%M:%S.%N | cut -c1-12)" "$*" >> "$OUT/case.log"; }
[ -n "${PRESETUP:-}" ] && bash -c "$PRESETUP" >> "$OUT/case.log" 2>&1
mkdir -p /tmp/.X11-unix 2>/dev/null; chmod 1777 /tmp/.X11-unix 2>/dev/null
if [ -n "${OUTPUT_MODE:-}${OUTPUT_SCALE:-}" ]; then
	export KWIN_VIRTUAL_STEREO_MODES=1
	kwin_wayland --virtual --socket=setup --width 1920 --height 1080 > "$OUT/setup-kwin.log" 2>&1 &
	SPID=$!
	for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/setup" ] && break; sleep 0.1; done; sleep 1.5
	args=$(WAYLAND_DISPLAY=setup kscreen-doctor -j 2>/dev/null | python3 -c '
import json, sys
mode, scale = sys.argv[1], sys.argv[2]
for o in json.load(sys.stdin)["outputs"]:
    if mode == "3d":
        m = [m for m in o["modes"] if m.get("stereo3D") == 1]
        if m:
            print("output.%s.mode.%s" % (o["name"], m[0]["id"]))
    if scale:
        print("output.%s.scale.%s" % (o["name"], scale))' "${OUTPUT_MODE:-}" "${OUTPUT_SCALE:-}")
	echo "kscreen-doctor $args" > "$OUT/setup-args.txt"
	# shellcheck disable=SC2086
	WAYLAND_DISPLAY=setup kscreen-doctor $args >> "$OUT/setup-args.txt" 2>&1; sleep 1.5
	WAYLAND_DISPLAY=setup kscreen-doctor -o 2>/dev/null | sed "s/\x1b\[[0-9;]*m//g" > "$OUT/setup-outputs.txt"
	kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
	# Display Settings saves a 3D twin with "Other stereo formats" on, and KWin restores the twin only then
	python3 - "$XDG_CONFIG_HOME/kwinoutputconfig.json" <<'PYCFG'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for sec in d:
    if sec.get("name") == "outputs":
        for o in sec["data"]:
            if o.get("mode", {}).get("flags", 0) & 0x20000:
                o["otherStereoFormats"] = True
json.dump(d, open(p, "w"), indent=1)
PYCFG
	rm -f "$XDG_RUNTIME_DIR"/setup*
fi
KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
	kwin_wayland --virtual --xwayland --socket=w --width 1920 --height 1080 > "$OUT/kwin.log" 2>&1 &
KPID=$!
for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/w" ] && break; sleep 0.2; done
[ -S "$XDG_RUNTIME_DIR/w" ] || { log "KWin did not start"; exit 1; }
export WAYLAND_DISPLAY=w DISPLAY=:0 QT_QPA_PLATFORM=${PLATFORM:-wayland}
sleep 2
cap() {
	python3 /proofrig/capture.py "$OUT/$1.png" > "$OUT/$1.json" 2>&1
	python3 /proofrig/kwin_windows.py "$OUT/kwin.log" > "$OUT/$1.windows.json" 2>&1
	if [ -n "${GEOM_FILE:-}" ] && [ -s "$GEOM_FILE" ]; then cp "$GEOM_FILE" "$OUT/$1.geom.txt"; fi
	log "capture $1 $(head -c 160 "$OUT/$1.json")"
}
env=(WAYLAND_DEBUG=client)
[ "${PROBE:-1}" = 1 ] && env+=(LD_PRELOAD="/probe/${PROBE_LIB:-r863-probe.so}${SHIM:+ /probe/$SHIM}" R863_OUT="$OUT")
log "start: ${PROG}"
# shellcheck disable=SC2086
env "${env[@]}" ${PROGENV:-} ${PROG} > "$OUT/stdout.txt" 2> "$OUT/stderr.txt" &
APID=$!
end=$(( $(date +%s) + ${CASE_TIMEOUT:-240} ))
if [ "${PROBE:-1}" = 1 ]; then
	k=0
	while [ "$(date +%s)" -lt "$end" ] && kill -0 "$APID" 2>/dev/null; do
		if [ -e "$OUT/step-$k.ready" ]; then cap "step-$k"; echo "$k" > "$OUT/step-$k.captured"; k=$((k + 1)); continue; fi
		[ -e "$OUT/done" ] && break
		sleep 0.2
	done
	log "probe steps captured: $k; done=$([ -e "$OUT/done" ] && echo 1 || echo 0)"
else
	[ -x /tmp/fi/fakeinput ] || sh /proofrig/build-fakeinput.sh /tmp/fi > /dev/null 2>&1
	sleep "${START_WAIT:-12}"
	cap step-0
	k=1
	IFS='^' read -r -a steps <<< "${EXT_STEPS:-}"
	for s in "${steps[@]}"; do
		case $s in
		kwin:*) python3 /proofrig/kwin_script.py "$OUT/kwin.log" "${s#kwin:}" >> "$OUT/case.log" 2>&1 ;;
		fi:*) /tmp/fi/fakeinput ${s#fi:} >> "$OUT/case.log" 2>&1 ;;
		sleep:*) sleep "${s#sleep:}" ;;
		esac
		log "step $k: $s"
		sleep "${STEP_WAIT:-3}"
		cap "step-$k"
		k=$((k + 1))
	done
	touch "$OUT/done"
fi
# which Qt the program's process really loaded
if kill -0 "$APID" 2>/dev/null; then
	for p in "$APID" $(pgrep -P "$APID" 2>/dev/null); do
		grep -o -E '/[^ ]*lib(Qt[56][A-Za-z]*|r863-probe)[^ ]*' "/proc/$p/maps" 2>/dev/null | sort -u | sed "s/^/pid $p: /"
	done > "$OUT/maps.txt"
fi
alive=$(kill -0 "$APID" 2>/dev/null && echo yes || echo no)
log "program alive at the end: $alive"
kill "$APID" 2>/dev/null; sleep 2; kill -9 "$APID" 2>/dev/null
wait "$APID" 2>/dev/null; log "program exit status $?"
kill "$KPID" 2>/dev/null; wait "$KPID" 2>/dev/null
exit 0
