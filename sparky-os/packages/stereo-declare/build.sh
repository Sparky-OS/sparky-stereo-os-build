#!/bin/bash
# Sparky Stereo OS: builds stereo-declare 1.4.0-1+lc1 (libstereo-declare1, libstereo-declare-dev, python3-stereo-declare)
# from a release clone of Sparky-OS/libstereo-declare, through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# The plain source package is made from the release commit (orig tarball without debian/, dated by the commit), then the
# Lean Code source, then the build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR CLONE   (PREVIOUS_DIR: the earlier +lc1 .deb files; CLONE: a clone holding REV)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
CLONE=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 -v "$WORK":/work -v "$PREV":/prev:ro \
	-v "$CLONE":/fork:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
