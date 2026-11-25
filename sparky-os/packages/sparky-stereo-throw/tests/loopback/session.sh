#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
# The person's session of the loopback proof, as uid 1000: a session bus, PipeWire and WirePlumber, a headless Stereo
# KWin (+stereo3d66) with one 1280x720 screen, the Throw daemon, then the scenario (scenario.py).
# Usage: session.sh OUT_DIR
set -u
OUT=${1:?out dir}
export XDG_RUNTIME_DIR=$OUT/run HOME=$OUT/home LANG=C.UTF-8
mkdir -p "$XDG_RUNTIME_DIR" "$HOME" "$OUT/frames"
chmod 700 "$XDG_RUNTIME_DIR"
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    exec dbus-run-session -- bash "$0" "$@"
fi
pipewire > "$OUT/pipewire.log" 2>&1 &
for i in $(seq 1 50); do [ -S "$XDG_RUNTIME_DIR/pipewire-0" ] && break; sleep 0.1; done
wireplumber > "$OUT/wireplumber.log" 2>&1 &
sleep 1
if [ -x /usr/lib/x86_64-linux-gnu/libexec/sparky-stereo-throwd ]; then
    # the installed package: KWin's own permission check, the desktop file the package ships
    DAEMON=/usr/lib/x86_64-linux-gnu/libexec/sparky-stereo-throwd
    CLI=sparky-stereo-throw
    CHECKS=
else
    DAEMON=/tools/bin/sparky-stereo-throwd
    CLI=/tools/bin/sparky-stereo-throw
    CHECKS=1
    export XDG_DATA_DIRS=/tools/share:/usr/share
fi
KWIN_WAYLAND_NO_PERMISSION_CHECKS=${CHECKS} KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 QT_LOGGING_RULES='kwin_screencast.debug=true;kwin_core.debug=false' \
    kwin_wayland --virtual --output-count 1 --width 1280 --height 720 --socket=w0 > "$OUT/kwin.log" 2>&1 &
for i in $(seq 1 100); do [ -S "$XDG_RUNTIME_DIR/w0" ] && break; sleep 0.1; done
export WAYLAND_DISPLAY=w0
sleep 2
if [ -z "$CHECKS" ]; then
    # the installed package as a person's session starts it: the session bus has the session's environment (Plasma's
    # login gives it), then starts the daemon from its D-Bus service file; the started executable is recorded, then it is
    # ended and started again by hand only so that its log is kept for the rows
    dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.UpdateActivationEnvironment \
        dict:string:string:WAYLAND_DISPLAY,w0,XDG_RUNTIME_DIR,"$XDG_RUNTIME_DIR",HOME,"$HOME" > /dev/null 2>&1
    if dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.StartServiceByName \
        string:org.sparky.Throw uint32:0 > "$OUT/activation.txt" 2>&1; then
        pid=$(dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID \
            string:org.sparky.Throw 2>/dev/null | awk '/uint32/ {print $2}')
        echo "activated: pid $pid, executable $(readlink "/proc/$pid/exe" 2>/dev/null)" >> "$OUT/activation.txt"
        [ -n "$pid" ] && kill "$pid"
        for i in $(seq 1 50); do dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.NameHasOwner string:org.sparky.Throw 2>/dev/null | grep -q true || break; sleep 0.2; done
    fi
fi
QT_LOGGING_RULES='org.sparky.throw.debug=true' "$DAEMON" > "$OUT/throwd.log" 2>&1 &
for i in $(seq 1 50); do dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.NameHasOwner string:org.sparky.Throw 2>/dev/null | grep -q true && break; sleep 0.2; done
echo "daemon $DAEMON, command $CLI, KWin permission checks $([ -n "$CHECKS" ] && echo off || echo on)" > "$OUT/session.txt"
python3 -I /tests/loopback/scenario.py "$OUT" "$CLI"
RC=$?
echo "scenario exit $RC" >> "$OUT/session.txt"
kill $(jobs -p) 2>/dev/null
wait 2>/dev/null
exit $RC
