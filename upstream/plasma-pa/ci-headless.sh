#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
# Sourced by kde-ci-local --build-setup in the disposable job shell.
set -e
: "${XDG_RUNTIME_DIR:?Private container runtime required}"
: "${CI_PROJECT_DIR:?CI checkout required}"
export WAYLAND_DISPLAY="$XDG_RUNTIME_DIR/pa19-weston"
export QT_QPA_PLATFORM=wayland GDK_BACKEND=wayland QT_QUICK_BACKEND=software
export TEST_WITH_KWIN_WAYLAND=0 TEST_WITH_VIDEO_RECORDER=0
export SELENIUM_OVERRIDE_LAUNCH='bash /pa19-ci/ci-app-launch.sh'
weston --no-config --backend=headless --renderer=pixman --socket=pa19-weston \
    --idle-time=0 --width=1600 --height=1200 --log="$CI_PROJECT_DIR/pa19-weston.log" &
pa19_weston_pid=$!
trap 'kill "$pa19_weston_pid" 2>/dev/null || true; wait "$pa19_weston_pid" 2>/dev/null || true' EXIT
for ((pa19_wait=0; pa19_wait<100; pa19_wait++)); do
    kill -0 "$pa19_weston_pid" || return 1
    if [[ -S $WAYLAND_DISPLAY ]]; then break; fi
    sleep .1
done
test -S "$WAYLAND_DISPLAY"
echo '## ORDER 19: private Weston headless/Pixman, software Qt Quick; all test assertions kept, optional video recorder off'
