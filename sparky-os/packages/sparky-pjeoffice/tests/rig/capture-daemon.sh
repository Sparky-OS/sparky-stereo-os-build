#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As root in the container: take the compositor-output capture the person's session asks for (a file OUT/want-NAME holding its XDG_RUNTIME_DIR). Stops when OUT/stop exists.
OUT=${1:?}
while [ ! -e "$OUT/stop" ]; do
  for w in "$OUT"/want-*; do
    [ -e "$w" ] || continue
    name=${w##*/want-}
    [ -s "$OUT/$name.png" ] && continue
    pid=$(pgrep -x kwin_wayland | head -1)
    [ -n "$pid" ] || continue
    KWIN_PID=$pid XDG_RUNTIME_DIR=$(cat "$w") KWIN_CAPTURE_WIDTH=1280 KWIN_CAPTURE_HEIGHT=800 python3 /rig/capture-qpainter.py "$OUT/$name.png" > "$OUT/capture-$name.txt" 2>&1
  done
  sleep 1
done
