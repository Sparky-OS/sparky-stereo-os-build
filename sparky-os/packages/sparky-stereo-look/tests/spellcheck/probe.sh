#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export WAYLAND_DISPLAY=wayland-0
/test-bin/sonnet-state > "$CASE/sonnet-state.json"
kcmshell6 kcmspellchecking > "$CASE/spellcheck-kcm.log" 2>&1 &
page_pid=$!
trap 'kill -TERM "$page_pid" 2>/dev/null || true' EXIT
sleep 4
kill -0 "$page_pid"
python3 /rig-scripts/login-splash/shot.py Virtual-0 "$CASE/spellcheck-page.png" > "$CASE/spellcheck-shot.json"
