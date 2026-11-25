#!/bin/bash
# Sparky Stereo OS: builds plasma-keyboard 6.7.4-2+stereo3d1+lc1 from Debian's 6.7.4-2 source package (row 71).
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Source package once (the patch after Debian's own, the changelog entry), then the Lean Code source, then the build with
# the link and start gate against Debian's build. Debian's packaging stays as Debian has it (nocheck); the pages and the
# first login are proved in the session rig apart from the package build.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR [IMAGE]   (PREVIOUS_DIR: a folder holding Debian's plasma-keyboard
#   6.7.4-1+b1 amd64 .deb for the link gate; SOURCE_DIR: the folder holding Debian's .dsc, .debian.tar.xz and .orig.tar.xz,
#   checked against Debian testing's signed Sources index; IMAGE: the build image, default sparky-lc-migration:20261020)
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
IMAGE=${4:-sparky-lc-migration:20261020}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
name=${NAME_PREFIX:-plasma-keyboard}-build-$$
sparky_provenance_init "$IMAGE"
docker create --ulimit core=1 --name "$name" --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro -v "$HERE/../../translations/plasma-keyboard-fcitx.po.patch":/translations/plasma-keyboard-fcitx.po.patch:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$IMAGE" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1' >/dev/null
[ -z "${CONTAINER_IDS:-}" ] || docker inspect -f '{{.Id}}' "$name" >> "$CONTAINER_IDS"
docker start "$name" >/dev/null
status=$(docker wait "$name")
docker rm "$name" >/dev/null
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/build.log" >&2; exit 1; }
