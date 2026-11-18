#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Run inside the login rig's private session bus after the desktop is ready.
set -euo pipefail
export WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland
kcmshell6 kcm_splashscreen > "$CASE/chooser.log" 2>&1 &
chooser_pid=$!
trap 'kill "$chooser_pid" 2>/dev/null || true' EXIT
sleep 3
python3 "$HERE/shot.py" Virtual-0 "$CASE/chooser.png" > "$CASE/chooser-shot.json"
if [ -n "${CHOOSER_STEPS:-}" ]; then
    read -r -a steps <<< "$CHOOSER_STEPS"
    python3 /rig-scripts/kwin_script.py "$CASE/session.log" 'print("CHOOSER_CURSOR_BEFORE", workspace.cursorPos)'
    /rig-tools/fakeinput s:500 "${steps[@]}" > "$CASE/chooser-input.log"
    python3 /rig-scripts/kwin_script.py "$CASE/session.log" 'print("CHOOSER_CURSOR_AFTER", workspace.cursorPos)' 
    sleep 1
    python3 "$HERE/shot.py" Virtual-0 "$CASE/chooser-selected.png" > "$CASE/chooser-selected-shot.json"
    [ ! -f "$HOME/.config/ksplashrc" ] || cp "$HOME/.config/ksplashrc" "$CASE/selected-ksplashrc"
fi
