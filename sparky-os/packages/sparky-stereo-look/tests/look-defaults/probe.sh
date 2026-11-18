#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export WAYLAND_DISPLAY=wayland-0
if [ "${EXPECT_USER:-0}" = 1 ]; then
 test -f "$HOME/.config/KDE/Sonnet.conf"
 cp "$HOME/.config/KDE/Sonnet.conf" "$CASE/user-Sonnet.conf"
else
 test ! -e "$HOME/.config/KDE/Sonnet.conf"
 echo 'PASS: no user Sonnet settings before native read' > "$CASE/system-fallback.txt"
fi
/test-bin/sonnet-state > "$CASE/sonnet-state.json"
/test-bin/notification-settings > "$CASE/notification-settings.json"
python3 - <<'PYCODE'
import json, os
from pathlib import Path
s=json.loads((Path(os.environ['CASE'])/'notification-settings.json').read_text())
assert s['permanentJobPopups'] == (os.environ.get('EXPECT_USER') == '1'), s
print('PASS: native notification setting and user precedence')
PYCODE
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
