#!/bin/bash
# Sparky Stereo OS: builds qt6-base 6.11.2+dfsg-5+stereo3d14+lc1 from the +stereo3d13 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23, +stereo3d13 2026/10/30, +stereo3d14 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Source package once (the rules change and the changelog entry), then the Lean Code source, then the build with the link
# and start gate against the earlier +lc1 builds, then test.sh on the new packages (their headers, as a program sees them).
# Candidates stay in WORK; the header test's logs in WORK/header-test.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder holding the +stereo3d13+lc1 .deb files;
#   SOURCE_DIR: the folder holding qt6-base_6.11.2+dfsg-5+stereo3d13.dsc, its debian.tar.xz and the orig tarball,
#   the plain source that sparky-os/repo/plain-from-lc.py makes from the published +lc1 source)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate's folder, mounted at /archive: sources.json (the public archives, and the edition's
  published tree as file:/repo) and the public keyrings it names; see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
bash "$HERE/test.sh" "$WORK/lc" "$WORK/header-test"
