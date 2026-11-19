#!/bin/bash
# Runs in the root's chroot as root (the lab's deep colour row). The same compositor start as the vkms bench's kwin-steps.sh; then for each
# layout named in /tmp/src/args.txt (2d: the plain 1920x1080@60 mode, sbs-half: the output's 3D side by side half mode): the ramp
# client (rig: tools/vkms-stereo-bench/src/deep-ramp.c, 256 values of a 16 bit channel) in each shm format the compositor advertises
# (16 bit AB48 or XB48, 10 bit AR30 or XR30, 8 bit XR24) fullscreen, and the 16 bit EGL pair (left ramp 0x8000.., right ramp 0x9000..) in a
# declared 3D area; the scanned-out frame is read back at 16 bits (drm-grab with DRM_GRAB_DEEP=1) for rows/deep_judge.py.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root XDG_RUNTIME_DIR=/run/user/0 LANG=C.UTF-8 LC_ALL=C.UTF-8 KWIN_DRM_DEVICES=/dev/dri/card0
mkdir -p $XDG_RUNTIME_DIR /tmp/bin && chmod 700 $XDG_RUNTIME_DIR
log() { echo "STEREO|deep|$*"; }
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec dbus-run-session -- sh /tmp/kwin-steps.sh
fi
layouts=$(cat /tmp/src/args.txt)
cd /tmp/src
xml=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $xml xdg-shell-client-protocol.h &&
wayland-scanner private-code $xml xdg-shell-protocol.c &&
gcc -O2 -o /tmp/bin/deep-ramp deep-ramp.c xdg-shell-protocol.c $(pkg-config --cflags --libs wayland-client wayland-egl egl gl) ||
    { echo "STEREO|check|deep/clients|FAIL|could not build the ramp client"; exit 1; }
cd /
kwin_wayland --drm --socket=wl-stereo --no-lockscreen --no-global-shortcuts --no-kactivities > /tmp/out/kwin.log 2>&1 &
kp=$!
i=0
while [ $i -lt 120 ] && [ ! -S $XDG_RUNTIME_DIR/wl-stereo ]; do sleep 0.5; i=$((i + 1)); done
log "socket after $i half seconds"
export WAYLAND_DISPLAY=wl-stereo
sleep 4
QT_QPA_PLATFORM=wayland kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > /tmp/out/kscreen-outputs.txt
output=$(grep -m1 '^Output:' /tmp/out/kscreen-outputs.txt | awk '{print $3}')
log "output ${output:-none}, $(grep -o '(3D-[A-Za-z-]*)' /tmp/out/kscreen-outputs.txt | wc -l) 3D modes listed"
mode_id() { tr ' ' '\n' < /tmp/out/kscreen-outputs.txt | grep -F ":$1" | grep -v -F "$1(" | head -1 | cut -d: -f1; }
grab_deep() { # grab_deep TAG: the scanned-out frame at 16 bits once it shows something
    t=0
    while [ $t -lt 30 ]; do
        sleep 1
        DRM_GRAB_DEEP=1 /tmp/drm-grab /dev/dri/card0 /tmp/out/$1.ppm > /tmp/out/grab-$1.txt 2>&1
        [ "$(sed -n 's/^nonblack //p' /tmp/out/grab-$1.txt)" -gt 0 ] 2>/dev/null && break
        t=$((t + 1))
    done
    log "$1: $(grep '^mode\|^fb' /tmp/out/grab-$1.txt | tr '\n' ' ')after $((t + 1)) grabs"
}
for lay in $layouts; do
    case $lay in
        2d) mode="1920x1080@60.00" ;;
        sbs-half) mode="1920x1080@60.00(3D-SBS)" ;;
        *) log "$lay: unknown layout"; continue ;;
    esac
    id=$(mode_id "$mode")
    if [ -z "$id" ]; then log "$lay: no mode $mode"; echo "STEREO|skip|deep/$lay|no mode $mode"; continue; fi
    QT_QPA_PLATFORM=wayland kscreen-doctor output.$output.mode.$id > /tmp/out/kscreen-$lay.txt 2>&1
    log "$lay: mode $mode (id $id), kscreen-doctor exit $?"
    sleep 4
    for fmt in auto xr30 xr24; do
        tag=$lay-shm-$fmt
        MODE=shm RAMP_FORMAT=$fmt HOLD_SECONDS=60 /tmp/bin/deep-ramp > /tmp/out/client-$tag.log 2>&1 &
        cp=$!; sleep 3; grab_deep $tag; kill $cp; wait $cp 2>/dev/null
        log "$tag: $(tr '\n' ';' < /tmp/out/client-$tag.log)"
    done
    tag=$lay-stereo
    LIBGL_ALWAYS_SOFTWARE=1 MODE=stereo HOLD_SECONDS=60 /tmp/bin/deep-ramp > /tmp/out/client-$tag.log 2>&1 &
    cp=$!; sleep 4; grab_deep $tag; kill $cp; wait $cp 2>/dev/null
    log "$tag: $(tr '\n' ';' < /tmp/out/client-$tag.log)"
    sleep 1
done
kill $kp
wait $kp
log "kwin exit $?"
