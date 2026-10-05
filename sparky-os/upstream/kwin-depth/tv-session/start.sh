#!/bin/bash
# A second desktop session for trying KWin's stereo depth, from a text console. Nothing is installed:
# the packages are unpacked in prefix/, the session has its own D-Bus session bus, configuration, cache,
# state and data folders in home/, and a Wayland socket of its own. Run it on a text console (tty3).
# BACKEND=virtual runs it headless instead (for tests); the default is the display (drm).
set -u
DIR=$(cd "$(dirname "$0")" && pwd)
BACKEND=${BACKEND:-drm}
# the newest build by default (levels, real shadows, the pointer); DEPTH_PREFIX=prefix (levels only) or
# prefix-depth3 (with real shadows) select an earlier one
P=$DIR/${DEPTH_PREFIX:-prefix-depth4}/usr
L=$P/lib/x86_64-linux-gnu

if [ "$BACKEND" = drm ] && { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }; then
    echo "This starts a session on the display: run it from a text console (log in on tty3), not from the desktop." >&2
    exit 1
fi
rm -f "$DIR/stop" "$DIR/session.env"
mkdir -p "$DIR/log" "$DIR/home"/{config,cache,state,data}

# a runtime folder of its own inside the user's (a Wayland socket, never wayland-0)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/kwin-depth
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

# nothing of the real desktop's configuration is read or written
export XDG_CONFIG_HOME=$DIR/home/config XDG_CACHE_HOME=$DIR/home/cache XDG_STATE_HOME=$DIR/home/state XDG_DATA_HOME=$DIR/home/data

# the depth build first, then the system
export PATH=$P/bin:$PATH
export LD_LIBRARY_PATH=$L${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export QT_PLUGIN_PATH=$L/qt6/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}
export QML2_IMPORT_PATH=$L/qt6/qml${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}
export QML_IMPORT_PATH=$L/qt6/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}
export XDG_DATA_DIRS=$P/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}
export DEPTH_SESSION_DIR=$DIR BACKEND

# the seed: the Oxygen look, the default limits, and the displays as he last chose them
seed() { # file group key value
    kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4"
}
if [ ! -e "$DIR/home/config/.seeded" ]; then
    seed kdeglobals KDE widgetStyle oxygen
    seed kdeglobals General ColorScheme OxygenDark
    seed kdeglobals Icons Theme oxygen
    seed plasmarc Theme name oxygen
    seed kcminputrc Mouse cursorTheme Oxygen_Black
    seed kwinrc org.kde.kdecoration2 library org.kde.oxygen
    touch "$DIR/home/config/.seeded"
fi

# the displays as he last chose them, copied once (a copy; the original is never touched)
if [ ! -e "$DIR/home/config/kwinoutputconfig.json" ] && [ -e "$HOME/.config/kwinoutputconfig.json" ]; then
    cp "$HOME/.config/kwinoutputconfig.json" "$DIR/home/config/kwinoutputconfig.json"
fi

# the limits start at the defaults every time; tune.sh changes them while the session runs
seed kwinrc StereoDepth SunkLimit 10
seed kwinrc StereoDepth PoppedLimit 4

# kded is not started, but a program may ask the session bus for it: its display module stays off,
# so nothing in this session applies a display configuration of its own (KDE Frameworks 6 still
# reads kded5rc)
seed kded5rc Module-kscreen autoload false
seed kded6rc Module-kscreen autoload false

exec dbus-run-session -- "$DIR/inner.sh" > "$DIR/log/session.log" 2>&1
