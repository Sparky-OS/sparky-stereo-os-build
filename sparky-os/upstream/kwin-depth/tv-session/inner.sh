#!/bin/bash
# inside the private session bus: starts KWin with the session script as its client
DIR=$DEPTH_SESSION_DIR
SOCKET=wayland-depth
# the variables for tune.sh, written once the session is up
(
    for _ in $(seq 1 120); do
        [ -S "$XDG_RUNTIME_DIR/$SOCKET" ] && break
        sleep 0.5
    done
    sleep 2
    {
        for v in DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME PATH LD_LIBRARY_PATH QT_PLUGIN_PATH XDG_DATA_DIRS; do
            printf 'export %s=%q\n' "$v" "${!v}"
        done
        printf 'export WAYLAND_DISPLAY=%q\n' "$SOCKET"
    } > "$DIR/session.env"
) &
if [ "$BACKEND" = virtual ]; then
    ARGS="--virtual --width ${SCREEN_W:-1280} --height ${SCREEN_H:-720} --output-count ${OUTPUTS:-1}"
else
    ARGS="--drm"
fi
kwin_wayland $ARGS --xwayland --socket=$SOCKET --exit-with-session "$DIR/session.sh"
echo "kwin_wayland ended with status $?"
