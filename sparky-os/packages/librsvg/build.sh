#!/bin/bash
# Sparky Stereo OS: builds librsvg 2.63.3+dfsg-1+stereo3d1+lc1 from Debian's 2.63.3+dfsg-1 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Source package once (the CSS colour patch after Debian's series, the changelog entry), then the Lean Code source, then
# the build with the link and start gate against Debian's 2.63.3+dfsg-1 build, then the colour test (ORDER 348).
# Debian vendors the Rust crates in debian/missing-sources, which Lean Code leaves as they are (lean/source_tree.py
# does not project debian/), so Cargo's checksums hold. Candidates stay in WORK; the colour test's results in
# WORK/colour-test. A guard stops the build below 12 GB free on / or 10 GB on the WORK disk (Rust builds fill disks).
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder holding the predecessor .deb files, Debian's
#   2.63.3+dfsg-1 build for this first one; SOURCE_DIR: the folder holding Debian's librsvg_2.63.3+dfsg-1.dsc, its
#   debian.tar.xz and the orig tarball, checked against Debian testing's signed Sources index)
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
name=librsvg-build-$$
docker run -d --name "$name" --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020 bash -c 'bash /tools/build-in-container.sh > /work/build.log 2>&1' >/dev/null
guard=ok
while [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ]; do
	root=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
	disk=$(df -BG --output=avail "$WORK" | tail -1 | tr -dc 0-9)
	if [ "$root" -lt 12 ] || [ "$disk" -lt 10 ]; then
		echo "stopping the build: / has ${root} GB and $WORK ${disk} GB free" >&2
		docker kill "$name" >/dev/null
		guard=stopped
	fi
	sleep 5
done
status=$(docker inspect -f '{{.State.ExitCode}}' "$name")
docker rm "$name" >/dev/null
[ "$guard" = ok ] && [ "$status" = 0 ] || { echo "the build failed (exit $status, guard $guard): $WORK/build.log" >&2; exit 1; }
bash "$HERE/../tests/css-colour/test.sh" rsvg "$WORK/lc" "$WORK/colour-test"
