#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export WAYLAND_DISPLAY=wayland-0
/test-bin/notification-settings > "$CASE/notification-settings.json"
python3 /defaults-probe/copy-popup.py
