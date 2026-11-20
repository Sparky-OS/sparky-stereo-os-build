#!/bin/bash
# Sparky Stereo OS: builds glib2.0 2.90.1-2+stereo3d1+lc1 from Debian's 2.90.1-2 source package (amd64; the i386 twin is
# build-i386.sh, from this build's +lc1 source package).
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# Source package once (upstream's commit 4301b49671 after Debian's series, the changelog entry), then the Lean Code source,
# then the build with the link and start gate against Debian's 2.90.1-2 build (ORDER 768). The test of the fix
# (tests/deadlock-reproducer/run.sh) runs apart from the package build, as Debian's packaging stays as Debian has it (nocheck).
# The build's jobs are not capped: dpkg-buildpackage -jauto.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder holding Debian's glib2.0 2.90.1-2 amd64 and all .deb
#   files for the link gate; SOURCE_DIR: the folder holding Debian's glib2.0_2.90.1-2.dsc, its debian.tar.xz and both orig
#   tarballs, checked against Debian testing's signed Sources index)
# SPARKY_BUILD_IMAGE names the builder image when it is not sparky-lc-migration:20261020.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the link gate's folder, mounted at /archive: sources.json (the public archives, and the edition's
  published tree as file:/repo) and the public keyrings it names; see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
PREV=$(cd "$2" && pwd)
SRC=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}
name=${SPARKY_BUILD_CONTAINER:-glib2.0-build-$$}
sparky_provenance_init "$IMAGE"
docker run -d --name "$name" --pull=never --ulimit core=0 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1' >/dev/null
status=$(docker wait "$name")
docker rm "$name" >/dev/null
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/build.log" >&2; exit 1; }
