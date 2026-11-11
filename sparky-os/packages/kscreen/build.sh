#!/bin/bash
# Sparky Stereo OS: builds kscreen 4:6.7.4-1+stereo3d12+lc1 from the +stereo3d11 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Source package once (the s12 patches after the series, the translations of
# sparky-os/translations/kscreen-wdisplays-menus.po.patch last, changelog entry), then the Lean Code
# source, then the build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR   (PREVIOUS_DIR: a folder holding the +stereo3d11+lc1 .deb files;
#   SOURCE_DIR: the folder holding kscreen_6.7.4-1+stereo3d11.dsc, its debian.tar.xz and the orig tarball with its .asc,
#   the plain source, which sparky-os/repo/plain-from-lc.py makes from the published +lc1 source)
# SPARKY_LC_SIBLINGS_FILE (optional): the authoritative current edition .deb paths the gate may resolve against, one per
#   line, as the next publication round's cohort.list holds them; the folders of the files are mounted read only.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
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
SIBLING_MOUNTS=()
if [ -n "${SPARKY_LC_SIBLINGS_FILE:-}" ]; then
	SIBLING_MOUNTS=(-v "$SPARKY_LC_SIBLINGS_FILE":/siblings.list:ro -e SPARKY_LC_SIBLINGS_FILE=/siblings.list)
	while read -r dir; do SIBLING_MOUNTS+=(-v "$dir":"$dir":ro); done < <(xargs -d '\n' -n1 dirname < "$SPARKY_LC_SIBLINGS_FILE" | sort -u)
fi
sparky_provenance_init sparky-lc-migration:20261020
docker run --rm --cpus 4 --platform linux/amd64 "${SIBLING_MOUNTS[@]}" \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$TOOLKIT":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro -v "$TRANSLATIONS":/translations:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	sparky-lc-migration:20261020 bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1'
