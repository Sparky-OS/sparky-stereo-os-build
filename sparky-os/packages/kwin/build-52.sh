#!/bin/bash
# Sparky Stereo OS: builds kwin 4:6.7.4-2+stereo3d52+lc1 from the published +stereo3d43+lc1 source package, carrying the s44 patches (ORDER 418), the s45 patches (ORDER 424), the s46 patches (ORDER 442), the s47 patches (ORDER 449, three Plasma/6.7 fixes), the s48 patches (ORDER 116) the s49 patches (ORDER 459), the s50 patches (ORDER 464) and the s51 patches (ORDER 466) and the s52 patches (ORDER 485), none published on its own.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, updated 2026/11/08.
# Copyright 2026 under the GNU GPL3 License
# Source package once (the s43 patches after the series, the XREAL EDIDs in the debian tarball, changelog entry), then the
# Lean Code source, then the build with the link and start gate against the earlier +lc1 builds. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR SOURCE_DIR EXTRA_DIR   (PREVIOUS_DIR: a folder holding the +stereo3d43+lc1 .deb files;
#   SOURCE_DIR: the folder holding kwin_6.7.4-2+stereo3d43+lc1.dsc, its debian.tar.xz and the orig tarball with its .asc,
#   the published +stereo3d43+lc1 source;
#   EXTRA_DIR: builds this one needs that the repository does not have yet, installed before its build dependencies;
#   an empty folder when it has them all, as for +stereo3d52)
# SIBLINGS_DIR / PREVIOUS_SIBLINGS_DIR (optional): a folder with siblings.txt (one /sib or /psib path per line) and the edition builds the
#   gate must see that the repository does not have yet: the snapshot for this build, and the one the previous build was qualified against.
# SPARKY_REPO_DIR must be a real apt repository (dists/mashtabba/main/binary-amd64/Packages), not a flat pool: the gate reads it as file:/repo.
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
EXTRA=$(cd "$4" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init "${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}"
docker run --rm --ulimit core=0 --name kwin-485-pkg --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	${SIBLINGS_DIR:+-v "$SIBLINGS_DIR":/sib:ro -e SPARKY_LC_SIBLINGS_FILE=/sib/siblings.txt} \
	${PREVIOUS_SIBLINGS_DIR:+-v "$PREVIOUS_SIBLINGS_DIR":/psib:ro -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/psib/siblings.txt} -v "$WORK":/work -v "$SRC":/src:ro -v "$EXTRA":/extra:ro \
	-v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v "$HERE/patches":/patches:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container-52.sh > /work/build.log 2>&1'
