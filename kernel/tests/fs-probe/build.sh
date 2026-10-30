#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# build.sh [IMAGE]: builds fs-probe as a static binary next to this script, in a container with gcc and the
# kernel's uAPI headers (the kernel build image has both), as the invoking user. No libdrm.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u XAUTHORITY \
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" -v "$HERE":/w "${1:-kernel-73-263-efi-rig:1}" \
	sh -c 'cd /w && gcc -O2 -Wall -Wextra -static -o fs-probe fs-probe.c'
sha256sum "$HERE/fs-probe"
