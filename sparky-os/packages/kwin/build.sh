#!/bin/bash
# Sparky Stereo OS: builds kwin 4:6.7.4-2+stereo3d32+lc1 from the +stereo3d31 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, +stereo3d32 on 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Source package once (the s32 patches after the series, changelog entry), then the Lean Code source, then the
# build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR [SOURCE_DIR]   (PREVIOUS_DIR: a folder holding the +stereo3d31+lc1 .deb files;
#   SOURCE_DIR: the folder holding kwin_6.7.4-2+stereo3d31.dsc, its debian.tar.xz and the orig tarball with its .asc,
#   by default the local repository's source folder, which holds only +lc1 sources: pass the folder of the plain +stereo3d31 source)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "${3:-$SPARKY_REPO_DIR/source}" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 -v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
