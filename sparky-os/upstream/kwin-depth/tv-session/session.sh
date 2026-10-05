#!/bin/bash
# KWin's client: the shell (wallpaper and panel) and a few ordinary programs. The session ends when the
# file stop appears next to this script or when Konsole's last window closes.
DIR=$DEPTH_SESSION_DIR
LOG=$DIR/log
rm -f "$DIR/stop"
export QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=KDE XDG_SESSION_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6
cd "$HOME"
/usr/lib/x86_64-linux-gnu/libexec/kglobalacceld > "$LOG/kglobalacceld.log" 2>&1 &
sleep 1
# the shell and the programs; the first program is the one whose last window ends the session
# (SHELL_CMD and PROGRAMS, programs separated by ;, are overridden by the headless test only)
SHELL_CMD=${SHELL_CMD:-plasmashell}
PROGRAMS=${PROGRAMS:-konsole --nofork;dolphin;kwrite;systemsettings}
$SHELL_CMD > "$LOG/shell.log" 2>&1 &
sleep "${SHELL_WAIT:-6}"
KONSOLE=
IFS=';' read -ra LIST <<< "$PROGRAMS"
for prog in "${LIST[@]}"; do
    $prog > "$LOG/$(basename "${prog%% *}").log" 2>&1 &
    [ -z "$KONSOLE" ] && KONSOLE=$!
done
while [ ! -e "$DIR/stop" ] && kill -0 $KONSOLE 2>/dev/null; do
    sleep 1
done
rm -f "$DIR/stop" "$DIR/session.env"
kill $(jobs -p) 2>/dev/null
sleep 1
exit 0
