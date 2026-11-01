#!/bin/bash
# Sparky Stereo OS: builds kscreen 4:6.7.4-1+stereo3d11+lc1 from the +stereo3d10 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Source package once (the s11 patches after the series, the translations of
# sparky-os/translations/kscreen-arrangement-view.po.patch last, changelog entry), then the Lean Code
# source, then the build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder holding the +stereo3d10+lc1 .deb files;
#   SOURCE_DIR: the folder holding kscreen_6.7.4-1+stereo3d10.dsc, its debian.tar.xz and the orig tarball with its .asc,
#   the plain source, which sparky-os/repo/plain-from-lc.py makes from the published +lc1 source)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=${SPARKY_TOOLKIT:-$HERE/../..}
. "$TOOLKIT/config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate's folder, mounted at /archive: sources.json (the public archives, and the edition's
  published tree as file:/repo) and the public keyrings it names; see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
TRANSLATIONS=${SPARKY_TRANSLATIONS:-$TOOLKIT/translations}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$TOOLKIT":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro -v "$TRANSLATIONS":/translations:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1'
