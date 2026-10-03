#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
SO=$PWD/libgl-stereo.so
D=$PWD/out/hacks
mkdir -p "$D"
run_one() {
    local name=$1
    shift
    local dir="$D/$name"
    mkdir -p "$dir"
    rm -f "$dir"/frame-*
    local rc=0
    timeout --foreground 4 env LD_PRELOAD="$SO" GL_STEREO=1 GL_STEREO_SEPARATION=2 \
        GL_STEREO_DUMP=30 GL_STEREO_DUMP_DIR="$dir" "$@" -geometry 640x360+0+0 \
        > "$dir/stdout.txt" 2> "$dir/stderr.txt" || rc=$?
    if [ "$rc" != 0 ] && [ "$rc" != 124 ]; then
        cat "$dir/stderr.txt" >&2
        return "$rc"
    fi
    python3 measure-hack.py "$dir" "$name"
}
run_one glxgears glxgears
run_one gears /usr/libexec/xscreensaver/gears -window
run_one molecule /usr/libexec/xscreensaver/molecule -window -no-shells -no-labels -no-titles
run_one rubik /usr/libexec/xscreensaver/rubik -window
