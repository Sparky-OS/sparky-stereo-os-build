#!/bin/bash
# Runs in the root's chroot as root (the lab's anaglyph case). The same compositor start as the vkms bench's kwin-steps.sh, in the
# plain 1920x1080@60 mode of the VKMS HDMI-A output; then the output's own "anaglyph" setting (kwinoutputconfig.json, the key
# Stereo KWin's output configuration holds) is switched on, KWin is started again, and the declared test client and a 2D
# client are shown. The scanned-out frames go to /tmp/out for rows/screens_judge.py anaglyph.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root XDG_RUNTIME_DIR=/run/user/0 LANG=C.UTF-8 LC_ALL=C.UTF-8 KWIN_DRM_DEVICES=/dev/dri/card0
mkdir -p $XDG_RUNTIME_DIR /tmp/bin && chmod 700 $XDG_RUNTIME_DIR
log() { echo "STEREO|kwin|$*"; }
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec dbus-run-session -- bash /tmp/anaglyph-steps.sh
fi
cd /tmp/src
xml=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $xml xdg-shell-client-protocol.h &&
wayland-scanner private-code $xml xdg-shell-protocol.c &&
gcc -O2 -o /tmp/bin/stereo-subsurface stereo-subsurface.c xdg-shell-protocol.c $(pkg-config --cflags --libs wayland-client wayland-egl egl gl) &&
gcc -O2 -o /tmp/bin/fullscreen-2d fullscreen-2d.c xdg-shell-protocol.c $(pkg-config --cflags --libs wayland-client) ||
    { echo "STEREO|check|kwin/clients|FAIL|could not build the test clients"; exit 1; }
cd /
start_kwin() {
    kwin_wayland --drm --socket=wl-stereo --no-lockscreen --no-global-shortcuts --no-kactivities > /tmp/out/kwin-$1.log 2>&1 &
    kp=$!
    i=0
    while [ $i -lt 120 ] && [ ! -S $XDG_RUNTIME_DIR/wl-stereo ]; do sleep 0.5; i=$((i + 1)); done
    export WAYLAND_DISPLAY=wl-stereo
    sleep 4
}
grab() { /tmp/drm-grab /dev/dri/card0 /tmp/out/kwin-$1.ppm > /tmp/out/grab-$1.txt 2>&1; }
grab_shown() {
    t=0
    while [ $t -lt 30 ]; do
        sleep 1
        grab $1
        [ "$(sed -n 's/^nonblack //p' /tmp/out/grab-$1.txt)" -gt 0 ] 2>/dev/null && break
        t=$((t + 1))
    done
    log "$1 after $((t + 1)) grabs"
}
start_kwin first
QT_QPA_PLATFORM=wayland kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > /tmp/out/kscreen-outputs.txt
output=$(grep -m1 '^Output:' /tmp/out/kscreen-outputs.txt | awk '{print $3}')
id=$(tr ' ' '\n' < /tmp/out/kscreen-outputs.txt | grep -F ":1920x1080@60.00" | grep -v "(" | head -1 | cut -d: -f1)
QT_QPA_PLATFORM=wayland kscreen-doctor output.$output.mode.$id > /tmp/out/kscreen-mode.txt 2>&1
sleep 3
cp /root/.config/kwinoutputconfig.json /tmp/out/kwinoutputconfig.before.json 2>/dev/null || log "no kwinoutputconfig.json written"
kill $kp; wait $kp 2>/dev/null
rm -f $XDG_RUNTIME_DIR/wl-stereo $XDG_RUNTIME_DIR/wl-stereo.lock
python3 - <<'PY' || log "could not edit kwinoutputconfig.json"
import json
p = "/root/.config/kwinoutputconfig.json"
d = json.load(open(p))
n = 0
for sec in d:
    if sec.get("name") == "outputs":
        for o in sec["data"]:
            o["anaglyph"] = True
            n += 1
json.dump(d, open(p, "w"), indent=1)
print("STEREO|kwin|anaglyph set on %d output(s)" % n)
PY
cp /root/.config/kwinoutputconfig.json /tmp/out/kwinoutputconfig.after.json
start_kwin anaglyph
log "anaglyph kwin started"
LIBGL_ALWAYS_SOFTWARE=1 HOLD_SECONDS=60 /tmp/bin/stereo-subsurface > /tmp/out/client-anaglyph.log 2>&1 &
cp=$!; sleep 2; grab_shown anaglyph-client; kill $cp; wait $cp 2>/dev/null
HOLD_SECONDS=60 /tmp/bin/fullscreen-2d > /tmp/out/client-anaglyph-fullscreen.log 2>&1 &
cp=$!; sleep 2; grab_shown anaglyph-fullscreen; kill $cp; wait $cp 2>/dev/null
kill $kp; wait $kp 2>/dev/null
log "kwin exit $?"
