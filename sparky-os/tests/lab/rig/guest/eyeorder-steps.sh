#!/bin/bash
# Runs in the root's chroot as root (the lab's eye order rows). The vkms bench's eyeorder/steps.sh (tools/vkms-stereo-bench/eyeorder) on
# the lab's guest: KWin on the VKMS card, the declared test client (left view red, right view green, blue 2D window), and for every
# mode tag named in /tmp/src/args.txt the output's mode set together with its swap eyes setting off and then on in one
# kscreen-doctor command, the scanned-out frame grabbed once two grabs a second apart are equal. eyeorder/analyze-eyeorder.py models
# every packing from the 2D reference frame and judges the frames. The twins of the "Anaglyph" and "Other stereo formats" toggles
# are made available with kscreen-doctor (output.NAME.anaglyph.enable, output.NAME.otherStereoFormats.enable), not by editing the
# stored configuration. Tags: plain anaglyph-modern anaglyph-crt twin-sbs-half twin-tab rows-left rows-right columns-left
# columns-right checkerboard-left checkerboard-right fs-left fs-right hdmi-sbs-half hdmi-tab hdmi-sbs-full hdmi-fp.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root XDG_RUNTIME_DIR=/run/user/0 LANG=C.UTF-8 LC_ALL=C.UTF-8 KWIN_DRM_DEVICES=/dev/dri/card0
mkdir -p $XDG_RUNTIME_DIR /tmp/bin && chmod 700 $XDG_RUNTIME_DIR
log() { echo "STEREO|eyeorder|$*"; }
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec dbus-run-session -- sh /tmp/kwin-steps.sh
fi
tags=$(cat /tmp/src/args.txt)
cd /tmp/src
xml=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $xml xdg-shell-client-protocol.h &&
wayland-scanner private-code $xml xdg-shell-protocol.c &&
gcc -O2 -o /tmp/bin/stereo-subsurface stereo-subsurface.c xdg-shell-protocol.c $(pkg-config --cflags --libs wayland-client wayland-egl egl gl) ||
    { echo "STEREO|check|eyeorder/clients|FAIL|could not build the test client"; exit 1; }
cd /
kwin_wayland --drm --socket=wl-stereo --no-lockscreen --no-global-shortcuts --no-kactivities > /tmp/out/kwin.log 2>&1 &
kp=$!
i=0
while [ $i -lt 120 ] && [ ! -S $XDG_RUNTIME_DIR/wl-stereo ]; do sleep 0.5; i=$((i + 1)); done
log "kwin: socket after $i half seconds"
export WAYLAND_DISPLAY=wl-stereo QT_QPA_PLATFORM=wayland
sleep 4
doctor() { kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > /tmp/out/doctor-$1.txt; }
doctor first
output=$(grep -m1 '^Output:' /tmp/out/doctor-first.txt | awk '{print $3}')
log "output ${output:-none}"
need_virtual=0
for t in $tags; do case $t in anaglyph-*|twin-*|rows-*|columns-*|checkerboard-*|fs-*) need_virtual=1 ;; esac; done
if [ $need_virtual = 1 ]; then
    kscreen-doctor output.$output.anaglyph.enable output.$output.otherStereoFormats.enable > /tmp/out/toggles.txt 2>&1
    log "toggles: kscreen-doctor exit $?, said: $(tr '\n' ' ' < /tmp/out/toggles.txt | head -c 160)"
    sleep 3
fi
doctor second
cat > /tmp/pick.py <<'PICK'
import re, sys
text = open("/tmp/out/doctor-second.txt").read()
want_tags = sys.argv[1:]
modes = {}
for m in re.finditer(r"(\d+):(\d+x\d+)@([0-9.]+)((?:\([^)]*\))*)[*!]*", text):
    key = (m.group(2), m.group(3), m.group(4))
    modes[key] = min(modes.get(key, 1 << 30), int(m.group(1)))
want = {
 "plain": ("1920x1080", "60.00", ""),
 "anaglyph-modern": ("1920x1080", "60.00", "(virtual-3D:5)"),
 "anaglyph-crt": ("1920x1080", "60.00", "(virtual-3D:6)"),
 "twin-sbs-half": ("1920x1080", "60.00", "(3D-SBS)(virtual-3D:1)"),
 "twin-tab": ("1920x1080", "60.00", "(3D-TaB)(virtual-3D:2)"),
 "rows-left": ("1920x1080", "60.00", "(virtual-3D:7)"),
 "rows-right": ("1920x1080", "60.00", "(virtual-3D:8)"),
 "columns-left": ("1920x1080", "60.00", "(virtual-3D:9)"),
 "columns-right": ("1920x1080", "60.00", "(virtual-3D:10)"),
 "checkerboard-left": ("1920x1080", "60.00", "(virtual-3D:11)"),
 "checkerboard-right": ("1920x1080", "60.00", "(virtual-3D:12)"),
 "fs-left": ("1920x1080", "120.00", "(virtual-3D:13)"),
 "fs-right": ("1920x1080", "120.00", "(virtual-3D:14)"),
 "hdmi-sbs-half": ("1920x1080", "60.00", "(3D-SBS)"),
 "hdmi-tab": ("1920x1080", "60.00", "(3D-TaB)"),
 "hdmi-sbs-full": ("1920x1080", "60.00", "(3D-SBS-full)"),
 "hdmi-fp": ("1920x1080", "24.00", "(3D-FP)"),
}
for tag, key in want.items():
    if tag == "plain" or tag in want_tags:
        print(tag, modes.get(key, ""))
    else:
        print(tag, "")
PICK
python3 /tmp/pick.py $tags > /tmp/out/modes.txt
log "modes: $(grep -c ' [0-9]' /tmp/out/modes.txt) of $(echo $tags | wc -w) asked for (and the plain mode) found"
LIBGL_ALWAYS_SOFTWARE=1 HOLD_SECONDS=3000 /tmp/bin/stereo-subsurface > /tmp/out/client-stereo.log 2>&1 &
cp=$!
sleep 6
log "client: $(head -1 /tmp/out/client-stereo.log)"
if ! kill -0 $cp 2>/dev/null; then
    # the declared client could not run (a compositor or Mesa without the stereo declaration): there is no picture to model
    log "the declared test client ended: $(tr '\n' ' ' < /tmp/out/client-stereo.log | head -c 200)"
    kill $kp; wait $kp
    log "kwin exit $?"
    exit 0
fi
grab() { # grab TAG: the output's frame once two grabs a second apart are the same
    t=0
    while [ $t -lt 20 ]; do
        /tmp/drm-grab /dev/dri/card0 /tmp/a.ppm > /tmp/a.txt 2>&1
        sleep 1
        /tmp/drm-grab /dev/dri/card0 /tmp/b.ppm > /tmp/b.txt 2>&1
        cmp -s /tmp/a.ppm /tmp/b.ppm && [ "$(sed -n 's/^nonblack //p' /tmp/b.txt)" -gt 0 ] 2>/dev/null && break
        t=$((t + 1))
    done
    cp /tmp/b.ppm /tmp/out/$1.ppm
    cp /tmp/b.txt /tmp/out/grab-$1.txt
    log "$1: $(grep '^mode\|^fb' /tmp/b.txt | tr '\n' ' ')after $((t + 1)) pairs"
}
setmode() { # setmode TAG SWAP(enable|disable)
    id=$(sed -n "s/^$1 //p" /tmp/out/modes.txt)
    if [ -z "$id" ]; then log "$1: no such mode"; return 1; fi
    kscreen-doctor output.$output.mode.$id output.$output.swapEyes.$2 > /tmp/out/set-$1-$2.txt 2>&1
    log "$1 swap $2: mode id $id, kscreen-doctor exit $?"
    sleep 3
}
setmode plain disable && grab ref
for tag in plain $tags; do
    for sw in disable enable; do
        n=$tag-s0; [ $sw = enable ] && n=$tag-s1
        setmode $tag $sw || continue
        grab $n
    done
done
setmode plain disable && grab back-2d
kill $cp 2>/dev/null; wait $cp 2>/dev/null
kill $kp; wait $kp
log "kwin exit $?"
