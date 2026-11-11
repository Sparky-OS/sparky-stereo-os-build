#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
# As an ordinary user: hand edits and daemon status under a fixture root.
set -eu
BUILD=${BUILD:?build tree}
OUT=${OUT:?results folder}
mkdir -p "$OUT"
W=$(mktemp -d "${TMPDIR:-/tmp}/memory-kcm.XXXXXX")
trap 'rm -rf "$W"' EXIT
SPARKY_STEREO_MEMORY_ROOT="$W" QT_QPA_PLATFORM=offscreen \
    "$BUILD/bin/memorykcmtest" handEditShows statusShows >"$OUT/memory-kcm.log" 2>&1
cat "$OUT/memory-kcm.log"
