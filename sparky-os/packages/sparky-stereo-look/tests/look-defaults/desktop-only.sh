#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
export WAYLAND_DISPLAY=wayland-0
python3 /defaults-probe/check-desktop.py
python3 /defaults-probe/test-seeding.py > "$CASE/once-only.json"
