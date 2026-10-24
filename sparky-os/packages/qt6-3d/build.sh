#!/bin/bash
# Sparky Stereo OS: builds qt6-3d 6.11.2+dfsg-2+stereo3d1+lc1 from Debian's 6.11.2+dfsg-2 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Source package once (the renderer-context patch after Debian's series, changelog entry), then the Lean Code source, then the
# build with the link and start gate. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder of earlier builds for the link gate, empty for
#   the first one; SOURCE_DIR: the folder holding Debian's qt6-3d_6.11.2+dfsg-2.dsc, its debian.tar.xz and the
#   orig tarball, pinned by the .dsc hash in build-in-container.sh)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 -v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
