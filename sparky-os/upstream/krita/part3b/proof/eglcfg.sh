#!/bin/bash
export XDG_RUNTIME_DIR=/tmp/rt-$$; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR; export HOME=/tmp/h
exec dbus-run-session -- bash -c 'kwin_wayland --virtual --xwayland --socket=sub --width 1280 --height 800 > /tmp/kw.log 2>&1 & kp=$!; for i in $(seq 1 80); do test -S $XDG_RUNTIME_DIR/sub && break; sleep .25; done; sleep 1; WAYLAND_DISPLAY=sub /k/t/eglcfg; kill $kp'
