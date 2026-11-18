#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export WAYLAND_DISPLAY=wayland-0
/test-bin/sonnet-state > "$CASE/sonnet-state.json"
/test-bin/home-labels > "$CASE/kde-home-labels.json"
/test-bin/notification-settings > "$CASE/notification-settings.json"
fail=0
python3 /defaults-probe/check-desktop.py || fail=1
kcmshell6 kcmspellchecking > "$CASE/spelling-page.log" 2>&1 &
page=$!
trap 'kill -TERM "$page" 2>/dev/null || true' EXIT
sleep 3
kill -0 "$page"
python3 /rig-scripts/login-splash/shot.py Virtual-0 "$CASE/spelling-page.png" > "$CASE/spelling-shot.json"
python3 /tests/spellcheck/check-inventory.py "$CASE/sonnet-state.json" || fail=1
exit "$fail"
