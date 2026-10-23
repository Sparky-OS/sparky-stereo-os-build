#!/bin/bash
# Sparky Stereo OS: builds plasma-union 6.8.80~git20261022.2163195c-0+stereo3d1+lc1 (kde-style-union) from Union master
# 2163195c with Debian's plasma-union packaging and the depth commits, through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# The orig tarball is made from the upstream commit (dated by the commit), Debian's packaging (debian-salsa, Salsa
# qt-kde-team/kde/plasma-union 1576d67, 6.7.4-2) gets the changelog entry and the patches, then the Lean Code source,
# then the build with its tests and the link and start gate. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR CLONE [STAGED]   (PREVIOUS_DIR: earlier builds for the link gate, empty for the first
#   one; CLONE: a clone of Union holding 2163195c; STAGED: a folder with the libstereo-declare1 and libstereo-declare-dev
#   1.5.0 .deb files when they are not in the local repository yet)
# UNION_CONTROL=1 builds the same source without the depth patches, as 6.8.80~git20261022.2163195c-0+control1, for the
#   proof rig's 2D and negative controls only; it is never published.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
CLONE=$(cd "$3" && pwd)
STAGED=()
[ -n "${4:-}" ] && STAGED=(-v "$(cd "$4" && pwd)":/staged:ro)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 -e UNION_CONTROL="${UNION_CONTROL:-}" -v "$WORK":/work -v "$CLONE":/fork:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro "${STAGED[@]}" -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
