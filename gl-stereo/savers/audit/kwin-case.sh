#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
run=$1
hack=$2
mkdir -p "$run"/{home,config,runtime}
chmod 700 "$run/runtime"
export HOME="$run/home" XDG_CONFIG_HOME="$run/config" XDG_RUNTIME_DIR="$run/runtime"
export KWIN_COMPOSE=O2 KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1 LP_NUM_THREADS=4
unset DISPLAY WAYLAND_DISPLAY LD_PRELOAD LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER
kwin_wayland --virtual --width 1024 --height 640 --xwayland --socket gl-stereo-audit --no-global-shortcuts \
    --exit-with-session "python3 /workspace/gl-stereo/savers/audit/kwin-client.py $run $hack" >"$run/kwin.log" 2>&1
