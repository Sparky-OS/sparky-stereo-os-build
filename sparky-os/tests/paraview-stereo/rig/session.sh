#!/bin/bash
# Inside a rig container: session.sh OUTDIR CASE [ARGS...]
# One fresh Stereo KWin session (virtual output W x H, Xwayland, no permission prompts), then CASE with WAYLAND_DISPLAY and
# DISPLAY set as a person's Plasma session has them. Limits: SUNK and POPPED (kwinrc [StereoDepth], default 10 and 4).
out=$1; shift; mkdir -p "$out"
export HOME=$out/home XDG_RUNTIME_DIR=$(mktemp -d /tmp/rt.XXXXXX) OUT=$out
mkdir -p $HOME/.config; chmod 700 $XDG_RUNTIME_DIR
export XDG_CONFIG_HOME=$HOME/.config
if [ -n "${SUNK:-}" ]; then printf '[StereoDepth]\nSunkLimit=%s\nPoppedLimit=%s\n' "$SUNK" "$POPPED" > $XDG_CONFIG_HOME/kwinrc; fi
printf '[Xwayland]\nXwaylandEisNoPrompt=true\n' >> $XDG_CONFIG_HOME/kwinrc
export KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 XDG_SESSION_TYPE=wayland
exec dbus-run-session -- bash -c '
kwin_wayland --virtual --xwayland --socket=w --width ${W:-1920} --height ${H:-1080} > $OUT/kwin.log 2>&1 & kp=$!
for i in $(seq 1 120); do test -S $XDG_RUNTIME_DIR/w && ls /tmp/.X11-unix/X* >/dev/null 2>&1 && break; sleep .25; done; sleep 2
export WAYLAND_DISPLAY=w DISPLAY=$(ls /tmp/.X11-unix | sed -n "s/^X/:/p" | head -1)
xprop -root _KDE_NET_WM_STEREO_CONTENT_SUPPORTED > $OUT/root.txt 2>&1
env ${CASE_ENV:-} "$@"; rc=$?
kill $kp; exit $rc' bash "$@"
