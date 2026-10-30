#!/bin/bash
# Sparky Stereo OS: builds kwin 4:6.7.4-2+stereo3d38+lc1 from the +stereo3d37 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, +stereo3d36 2026/10/29, +stereo3d37 and +stereo3d38 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Source package once (the s38 patches and the wallpaper-cost translations after the series, changelog entry), then the Lean Code source, then the
# build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR EXTRA_DIR   (PREVIOUS_DIR: a folder holding the +stereo3d37+lc1 .deb files;
#   SOURCE_DIR: the folder holding kwin_6.7.4-2+stereo3d37.dsc, its debian.tar.xz and the orig tarball with its .asc,
#   the plain source the +stereo3d37 build left beside its +lc1 one (or plain-from-lc.py's from the published +lc1 source);
#   EXTRA_DIR: the plasma-wayland-protocols 1.21.0-1+stereo3d10+lc1 .deb this build needs, installed before its
#   build dependencies while the repository does not have it yet; an empty folder once it does)
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
EXTRA=$(cd "$4" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$EXTRA":/extra:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
