#!/bin/bash
# Sparky Stereo OS: builds command-not-found 23.04.0-3+sparky1+lc1 from Debian's 23.04.0-3 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Source package once (patches/sparky-renamed-commands.patch and the table renamed-commands after Debian's series, the
# changelog entry), then the Lean Code source, then the build with its own tests and the link and start gate against
# Debian's 23.04.0-3 build (ORDER 252b, study row J15). The table is made by make-renamed.py; see README.md.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder holding the predecessor .deb, Debian's
#   command-not-found_23.04.0-3_all.deb for this first one; SOURCE_DIR: the folder holding Debian's
#   command-not-found_23.04.0-3.dsc, its debian.tar.xz and the orig tarball, as apt-get source downloads them)
# The candidates and their SHA256SUMS land in WORK/out. Workstation paths come from the local configuration:
# sparky-os/config/build.conf.example.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate's folder, mounted at /archive: sources.json (the public archives, and the edition's
  published tree as file:/repo) and the public keyrings it names; see sparky-os/lean/archive.md}"
# Docker mounts no symlink: the published tree by its real path
REPO=$(readlink -f "$SPARKY_REPO_DIR")
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
name=command-not-found-build-$$
sparky_provenance_init sparky-lc-migration:20261020
docker run -d --name "$name" --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$REPO":/repo:ro -v "$PREV":/prev:ro \
	-v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1' >/dev/null
status=$(docker wait "$name")
docker rm "$name" >/dev/null
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/build.log" >&2; exit 1; }
mkdir -p "$WORK/out/source"
cp "$WORK"/lc/*+lc1_*.deb "$WORK/out/"
cp "$WORK"/lc/command-not-found_23.04.0-3+sparky1+lc1.dsc "$WORK"/lc/command-not-found_23.04.0-3+sparky1+lc1.debian.tar.xz \
	"$WORK"/lc/command-not-found_23.04.0.orig.tar.xz "$WORK/out/source/"
(cd "$WORK/out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
