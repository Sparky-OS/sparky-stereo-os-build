#!/bin/bash
# Sparky Stereo OS: builds sview 26.9+stereo3d1+lc1 from a clone of Sparky-OS/sview (branch stereo-kwin), through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# The plain source package is made from the commit (a native package: debian/ is in the tree), then the Lean Code
# source, then the build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR CLONE LIBS_DIR
#   (PREVIOUS_DIR: the earlier +lc1 .deb files, an empty folder for a first build; CLONE: a clone holding the commit;
#    LIBS_DIR: the folder holding libstereo-declare1 and libstereo-declare-dev 1.6.0 or later)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
CLONE=$(cd "$3" && pwd)
LIBS=$(cd "$4" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 -v "$WORK":/work -v "$PREV":/prev:ro -v "$LIBS":/libs:ro -v "$SPARKY_REPO_DIR":/repo:ro \
	-v "$CLONE":/fork:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
