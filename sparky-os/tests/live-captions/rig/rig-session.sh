#!/bin/bash
set -euo pipefail
out=${1:?output directory}
scale=${2:?scale}
mode=${3:-captions}
export HOME="$out/home" XDG_CONFIG_HOME="$out/home/.config" XDG_DATA_HOME="$out/home/.local/share" XDG_CACHE_HOME="$out/home/.cache"
export XDG_RUNTIME_DIR="$out/runtime" LANG=C.UTF-8 LC_ALL=C.UTF-8
export QT_FORCE_STDERR_LOGGING=1 QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 KWIN_VIRTUAL_STEREO_MODES=1
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || true; done; }
trap cleanup EXIT
cat /proc/loadavg > "$out/load-before.txt"
kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --no-kactivities --socket lc73 --width 1920 --height 1080 > "$out/kwin.log" 2>&1 &
pids+=("$!")
for n in {1..120}; do [ -S "$XDG_RUNTIME_DIR/lc73" ] && break; sleep 0.25; done
[ -S "$XDG_RUNTIME_DIR/lc73" ]
export WAYLAND_DISPLAY=lc73 QT_QPA_PLATFORM=wayland
kscreen-doctor -j > "$out/outputs-before.json"
mapfile -t display < <(python3 - "$out/outputs-before.json" <<'PY'
import json,sys
out=json.load(open(sys.argv[1]))['outputs'][0]
modes=out['modes']; modes=modes.values() if isinstance(modes,dict) else modes
mode=next(m for m in modes if m.get('stereo3D')==1 and m['size']['width']==1920 and m['size']['height']==1080)
print(out['name']); print(mode['id'])
PY
)
[ "${#display[@]}" = 2 ]
kscreen-doctor "output.${display[0]}.mode.${display[1]}" "output.${display[0]}.scale.$scale" > "$out/set-output.txt" 2>&1
kscreen-doctor -j > "$out/outputs.json"
plasmashell --no-respawn > "$out/plasma.log" 2>&1 &
pids+=("$!")
python3 /proof/atspi-listen.py "$out/atspi.jsonl" > "$out/atspi.log" 2>&1 &
pids+=("$!")
if [ "$mode" = first-start ]; then
    strace -ff -e trace=network,process,openat -o "$out/first-start.trace" kaption --verbose > "$out/kaption.log" 2>&1 &
    pids+=("$!")
    sleep 10
    python3 /proof/kwin_windows.py "$out/kwin.log" > "$out/windows-first-start.json"
    python3 /proof/capture.py "$out/first-start.png" > "$out/first-start-capture.json"
    python3 /proof/mark_pns.py "$out/first-start.png" "$out/first-start.pns" > "$out/first-start-mark.txt"
    find "$HOME" -type f -printf '%P %s bytes\n' > "$out/first-start-files.txt"
    ps -eo pid,comm,args > "$out/first-start-processes.txt"
    cat /proc/loadavg > "$out/load-after.txt"
    exit 0
fi
export CAPTIOND_SOCKET="$XDG_RUNTIME_DIR/fixture.sock"
/proof-bin/stand-in "$CAPTIOND_SOCKET" /usr/share/captiond/testing/fox.wav "$out/stand-in.json" > "$out/stand-in.log" 2>&1 &
pids+=("$!")
for n in {1..120}; do [ -S "$CAPTIOND_SOCKET" ] && break; sleep 0.1; done
[ -S "$CAPTIOND_SOCKET" ]
WAYLAND_DEBUG=client kaption --verbose > "$out/kaption.log" 2>&1 &
pids+=("$!")
sleep 5
python3 /proof/kwin_windows.py "$out/kwin.log" > "$out/windows-desktop.json"
python3 /proof/capture.py "$out/desktop.png" > "$out/desktop-capture.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["width"]==3840 and d["height"]==1080,d' "$out/desktop-capture.json"
python3 /proof/mark_pns.py "$out/desktop.png" "$out/desktop.pns" > "$out/desktop-mark.txt"
WAYLAND_DEBUG=client mpv --no-config --no-audio --loop-file=inf --fullscreen --vo=gpu-next --gpu-context=wayland /fixtures/stereo.mkv > "$out/mpv.log" 2>&1 &
pids+=("$!")
sleep 5
python3 /proof/kwin_windows.py "$out/kwin.log" > "$out/windows-video.json"
python3 /proof/capture.py "$out/video.png" > "$out/video-capture.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["width"]==3840 and d["height"]==1080,d' "$out/video-capture.json"
python3 /proof/mark_pns.py "$out/video.png" "$out/video.pns" > "$out/video-mark.txt"
cat /proc/loadavg > "$out/load-after.txt"
