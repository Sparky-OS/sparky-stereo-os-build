#!/bin/bash
# Sparky Stereo OS: builds sview 26.9+stereo3d2+lc1 from a clone of Sparky-OS/sview, through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/24, +stereo3d2 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# The plain source package is made from the commit (a native package: debian/ is in the tree), then the Lean Code
# source, then the build with the link and start gate against the earlier +lc1 builds, then the one-output check
# (ORDER 312: Stereo KWin's output only). Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR CLONE
#   (PREVIOUS_DIR: the earlier +lc1 .deb files, an empty folder for a first build; CLONE: a clone holding the commit)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate's folder, mounted at /archive: sources.json (the public archives, and the edition's
  published tree as file:/repo) and the public keyrings it names; see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
CLONE=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$PREV":/prev:ro -v "$SPARKY_REPO_DIR":/repo:ro \
	-v "$CLONE":/fork:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
