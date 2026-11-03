#!/bin/bash
# Sparky Stereo OS: command-not-found's renamed commands in bash, zsh, fish, KRunner and Dolphin's packs (ORDER 252b, J15).
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Usage: test-callers.sh CANDIDATES OUT [IMAGE]
#   CANDIDATES: a folder holding the candidate command-not-found and sparky-stereo-integration .deb files;
#   OUT: a new folder for the results; IMAGE: an amd64 Debian testing image (default debian:testing, pin it by digest).
# Red runs on today's packages (Debian's command-not-found, the published sparky-stereo-integration and
# sparky-stereo-console), green after installing the candidates over them; check-callers.py judges both. The published
# edition tree comes from the local configuration (SPARKY_REPO_DIR, sparky-os/config/build.conf.example).
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
REPO=$(readlink -f "$SPARKY_REPO_DIR")
CAND=$(cd "$1" && pwd)
OUT=$(mkdir -p "$2" && cd "$2" && pwd)
IMAGE=${3:-debian:testing}
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
docker run --rm --cpus 4 --platform linux/amd64 --network bridge \
	-v "$REPO":/repo:ro -v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro -v "$CAND":/cand:ro -v "$HERE":/tests:ro -v "$OUT":/out \
	"$IMAGE" bash -c 'trap "chown -R '"$(id -u):$(id -g)"' /out" EXIT; bash /tests/callers-in-container.sh' 2>&1 | tee "$OUT/test.log"
