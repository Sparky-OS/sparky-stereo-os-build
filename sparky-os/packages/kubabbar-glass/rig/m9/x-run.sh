#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# x-run.sh COMMAND [ARGUMENT...]: COMMAND in a fresh X server (Xvfb, no window manager), as gtk-gallery.sh starts one;
# the server is stopped by its PID and COMMAND's exit status returned. xvfb-run is not used: in a container without an
# init it waits for its server after the command has ended (row 147, milestone 3).
set -uo pipefail
display=:$(( 50 + RANDOM % 400 ))
Xvfb "$display" -screen 0 1280x1024x24 -nolisten tcp > /dev/null 2>&1 &
xvfb=$!
trap 'kill "$xvfb" 2>/dev/null || true' EXIT
export DISPLAY=$display
for _ in $(seq 50); do
	xdpyinfo > /dev/null 2>&1 && break
	sleep 0.1
done
"$@"
