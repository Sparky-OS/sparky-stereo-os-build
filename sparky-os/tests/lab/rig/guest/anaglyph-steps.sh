#!/bin/bash
# Runs in the root's chroot as root (the lab's anaglyph diagnosis, queue row 733). The same compositor start as the vkms bench's
# kwin-steps.sh. The declared test client (left view red, right view green, blue 2D window) is shown under four ways of asking for
# an anaglyph output, each in a fresh KWin start, and the scanned-out frame of each is grabbed:
#   plain     nothing asked: the control, the area is the left view alone (red)
#   file      the stored "anaglyph": true on the output in kwinoutputconfig.json and nothing else (what the first milestone tried)
#   filemode  that and the stored mode of the output with the anaglyph modern layout (VirtualStereo 0x20000 + 0x200) in its flags
#   doctor    no file: kscreen-doctor output.NAME.anaglyph.enable, then the output's mode "(virtual-3D:5)" by its id
# Each variant also records kscreen-doctor -o (the mode list and the current mode) and the output's anaglyph line.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root XDG_RUNTIME_DIR=/run/user/0 LANG=C.UTF-8 LC_ALL=C.UTF-8 KWIN_DRM_DEVICES=/dev/dri/card0
mkdir -p $XDG_RUNTIME_DIR /tmp/bin && chmod 700 $XDG_RUNTIME_DIR
log() { echo "STEREO|anaglyph|$*"; }
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec dbus-run-session -- sh /tmp/kwin-steps.sh
fi
cd /tmp/src
xml=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $xml xdg-shell-client-protocol.h &&
wayland-scanner private-code $xml xdg-shell-protocol.c &&
gcc -O2 -o /tmp/bin/stereo-subsurface stereo-subsurface.c xdg-shell-protocol.c $(pkg-config --cflags --libs wayland-client wayland-egl egl gl) ||
    { echo "STEREO|check|anaglyph/clients|FAIL|could not build the test client"; exit 1; }
cd /
start_kwin() { # start_kwin TAG
    kwin_wayland --drm --socket=wl-stereo --no-lockscreen --no-global-shortcuts --no-kactivities > /tmp/out/kwin-$1.log 2>&1 &
    kp=$!
    i=0
    while [ $i -lt 120 ] && [ ! -S $XDG_RUNTIME_DIR/wl-stereo ]; do sleep 0.5; i=$((i + 1)); done
    export WAYLAND_DISPLAY=wl-stereo QT_QPA_PLATFORM=wayland
    sleep 4
}
stop_kwin() {
    kill $kp; wait $kp 2>/dev/null
    rm -f $XDG_RUNTIME_DIR/wl-stereo $XDG_RUNTIME_DIR/wl-stereo.lock
}
doctor() { kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > /tmp/out/outputs-$1.txt; }
grab_shown() { # grab_shown TAG
    t=0
    while [ $t -lt 30 ]; do
        sleep 1
        /tmp/drm-grab /dev/dri/card0 /tmp/out/$1.ppm > /tmp/out/grab-$1.txt 2>&1
        [ "$(sed -n 's/^nonblack //p' /tmp/out/grab-$1.txt)" -gt 0 ] 2>/dev/null && break
        t=$((t + 1))
    done
    log "$1 after $((t + 1)) grabs: $(grep '^mode' /tmp/out/grab-$1.txt)"
}
shoot() { # shoot TAG: the declared client on the running KWin, the frame grabbed
    LIBGL_ALWAYS_SOFTWARE=1 HOLD_SECONDS=60 /tmp/bin/stereo-subsurface > /tmp/out/client-$1.log 2>&1 &
    cp=$!; sleep 3
    if kill -0 $cp 2>/dev/null; then grab_shown $1; else log "$1: the declared test client ended: $(tr '\n' ' ' < /tmp/out/client-$1.log | head -c 160)"; fi
    kill $cp 2>/dev/null; wait $cp 2>/dev/null
}
edit_config() { # edit_config PYTHON-EXPRESSION on o: the dict of one output
    python3 - "$1" <<'PY'
import json, sys
p = "/root/.config/kwinoutputconfig.json"
d = json.load(open(p))
n = 0
for sec in d:
    if sec.get("name") == "outputs":
        for o in sec["data"]:
            exec(sys.argv[1])
            n += 1
json.dump(d, open(p, "w"), indent=1)
print("STEREO|anaglyph|edited %d output(s): %s" % (n, sys.argv[1]))
PY
}
mode_flags_modern='o["anaglyph"] = True; o["mode"] = {"width": 1920, "height": 1080, "refreshRate": 60000, "flags": 131584}'

# the first start writes the output's configuration; this is also the control
start_kwin plain
doctor plain
output=$(grep -m1 '^Output:' /tmp/out/outputs-plain.txt | awk '{print $3}')
log "output ${output:-none}; kscreen-doctor knows anaglyph: $(kscreen-doctor --help 2>&1 | grep -c -i anaglyph) help lines"
shoot plain
stop_kwin
cp /root/.config/kwinoutputconfig.json /tmp/out/config-plain.json 2>/dev/null || log "no kwinoutputconfig.json written"

edit_config 'o["anaglyph"] = True'
start_kwin file
doctor file
shoot file
stop_kwin

edit_config "$mode_flags_modern"
start_kwin filemode
doctor filemode
shoot filemode
stop_kwin

# back to the plain configuration, then only the command line
cp /tmp/out/config-plain.json /root/.config/kwinoutputconfig.json
edit_config 'o["anaglyph"] = False'
start_kwin doctor
kscreen-doctor output.$output.anaglyph.enable > /tmp/out/doctor-enable.txt 2>&1
log "kscreen-doctor output.$output.anaglyph.enable: exit $?, said: $(tr '\n' ' ' < /tmp/out/doctor-enable.txt | head -c 200)"
sleep 3
doctor doctor-after-enable
id=$(tr ' ' '\n' < /tmp/out/outputs-doctor-after-enable.txt | grep -F "1920x1080@60.00(virtual-3D:5)" | head -1 | cut -d: -f1)
log "the anaglyph modern mode of 1920x1080@60 has id '${id:-none}'"
if [ -n "$id" ]; then
    kscreen-doctor output.$output.mode.$id > /tmp/out/doctor-mode.txt 2>&1
    log "kscreen-doctor output.$output.mode.$id: exit $?"
    sleep 4
fi
doctor doctor-after-mode
shoot doctor
stop_kwin
log "done"
