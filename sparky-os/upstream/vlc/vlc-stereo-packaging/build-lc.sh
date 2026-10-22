#!/bin/bash
# Sparky Stereo OS: builds vlc-stereo VERSION+lc1 from the published source package of the version before it.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Source package once (the published BASE plus the patches ../0NNN-*.patch from FIRST on, inserted after Debian's and
# the earlier stereo patches, and the changelog entry of VERSION from the file "changelog"), then the Lean Code source,
# then the build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build-lc.sh WORK PREVIOUS_DIR   (PREVIOUS_DIR: a folder holding the BASE+lc1 .deb files)
# BASE (default 3.0.24-1+stereo3d9), VERSION (default 3.0.24-1+stereo3d10) and FIRST (default 27) may be set.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 -v "$WORK":/work -v "$SPARKY_REPO_DIR/source":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/..":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-e BASE="${BASE:-3.0.24-1+stereo3d9}" -e VERSION="${VERSION:-3.0.24-1+stereo3d10}" -e FIRST="${FIRST:-27}" \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-lc-in-container.sh > /work/build.log 2>&1'
