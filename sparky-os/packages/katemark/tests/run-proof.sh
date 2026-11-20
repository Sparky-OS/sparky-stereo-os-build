#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# Runs inside the proof image (ORDER 51): a virtual Stereo KWin session with no network, Kate opened on proof.md, the plugin looked for,
# the preview opened with Ctrl+Shift+M, the editor moved to the end, a plain PNG captured after each step.
# Usage (in the container, as the user the image's owner): run-proof.sh OUT SKILL_SCRIPTS FIXTURE [ENABLE]   ENABLE=1 writes katerc so Kate loads the plugin
set -uo pipefail
OUT=${1:?output folder} SK=${2:?stereo-proof-rig scripts folder} FIX=${3:?proof.md} ENABLE=${4:-1}
mkdir -p "$OUT"
export HOME=$OUT/home XDG_RUNTIME_DIR=$OUT/run XDG_CONFIG_HOME=$OUT/home/.config XDG_DATA_HOME=$OUT/home/.local/share XDG_CACHE_HOME=$OUT/home/.cache
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"; chmod 700 "$XDG_RUNTIME_DIR"
cp "$FIX" "$OUT/proof.md"
if [ "$ENABLE" = 1 ]; then
	printf '[Kate Plugins]\nkatemarkplugin=true\nkatemark=true\n' > "$XDG_CONFIG_HOME/katerc"
fi
ip -brief addr > "$OUT/network.txt" 2>&1
getent hosts github.com > "$OUT/dns-github.txt" 2>&1; echo "getent exit $?" >> "$OUT/dns-github.txt"
sh "$SK/build-fakeinput.sh" "$OUT/fi" > "$OUT/fi-build.log" 2>&1
cat > "$OUT/inner.sh" <<'IN'
set -u
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 LIBGL_ALWAYS_SOFTWARE=1 QT_QPA_PLATFORM=wayland
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --no-sandbox" QT_LOGGING_RULES="kf.coreaddons.debug=true;katemark*=true"
cd "$OUT"
kwin_wayland --virtual --xwayland --socket=sub --width 1600 --height 1000 > kwin.log 2>&1 &
for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/sub" ] && break; sleep 0.2; done
export WAYLAND_DISPLAY=sub
mkfifo fi-in fi-ack
"$OUT/fi/fakeinput" --serve fi-in fi-ack > fakeinput.log 2>&1 &
exec 7<>fi-in 8<>fi-ack
inp() { echo "$*" >&7; read -t 20 -r a <&8; echo "inp $* -> $a" >> inputs.log; }
kate -n "$OUT/proof.md" > kate.log 2>&1 &
KP=$!
sleep 15
python3 "$SK/capture.py" 01-kate-opened.png > cap1.json 2>&1
inp "m:800,500 b:272 s:300"
inp "k:42+29+50 s:12000"
python3 "$SK/capture.py" 02-after-ctrl-shift-m.png > cap2.json 2>&1
inp "m:300,500 b:272 s:300 k:29+107 s:8000"
python3 "$SK/capture.py" 03-editor-moved-to-end.png > cap3.json 2>&1
inp "k:29+102 s:8000"
python3 "$SK/capture.py" 04-editor-moved-to-start.png > cap4.json 2>&1
sleep 2
kill $KP 2>/dev/null; sleep 2
IN
export OUT SK
dbus-run-session -- bash "$OUT/inner.sh" > "$OUT/session.log" 2>&1
echo "run-proof finished"
