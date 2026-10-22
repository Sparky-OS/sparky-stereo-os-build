#!/bin/bash
# Sparky Stereo OS: builds one package of the full side by side round through Lean Code (see build-in-container.sh).
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Usage: build.sh PACKAGE WORK PUB PREVIOUS_DIR NEW_DIR [FORK_CLONE]
#   PACKAGE: mpv-dmo mpvqt mlt kdenlive qt6-multimedia spice-gtk karton qemu stereo-layer stereo-declare
#   PUB: the signed tree the build resolves its dependencies from; PREVIOUS_DIR: the earlier +lc1 .deb files of the package;
#   NEW_DIR: a flat repository (Packages, Release) of the debs built earlier in the round; FORK_CLONE: the release clone
#   (stereo-layer and stereo-declare only).
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
PKG=$1
WORK=$(mkdir -p "$2" && cd "$2" && pwd)
PUB=$(cd "$3" && pwd)
PREV=$(cd "$4" && pwd)
NEW=$(cd "$5" && pwd)
FORK=${6:+$(cd "$6" && pwd)}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --name "full-sbs-$PKG" --cpus 4 --platform linux/amd64 -e PKG="$PKG" -v "$WORK":/work \
	-v "$SPARKY_REPO_DIR/source":/src:ro -v "$PUB":/pub:ro -v "$NEW":/new:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE/patches":/patches:ro -v "$HERE/changelog":/changelog:ro \
	${FORK:+-v "$FORK":/fork:ro} \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /toolkit/packages/full-sbs/build-in-container.sh > /work/build.log 2>&1'
