#!/bin/bash
# Sparky Stereo OS: sparky-stereo-browser 6.7.5-0+stereo3d6+lc1 through Lean Code, stating its true source (ORDER 193, 6a-2).
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# The published stereo3d5+lc1 source package supplies the unchanged orig tarball (so no pool conflict); this recipe adds the quilt
# patches of the series (browser/0001: the site mark, Gecko commit 075e18be19 over the orig's b1d115f8d3; browser/0002: SOURCE.edition.json
# and so the source's own description name that commit), the new changelog entries, the Depends on libstereo-policy1 (>= 1.13.0), the
# MOZ_SOURCE_CHANGESET and the vendor baseline's commit; makes the new source package with dpkg-source -b and builds from it, with the
# build record's host facts (build-provenance.sh).
# Usage: build-browser.sh WORK PUBLISHED_DIR TOOLCHAIN_ROOT
#   WORK: an empty job folder; PUBLISHED_DIR: the published pool folder of sparky-stereo-browser (dsc, debian.tar.xz, orig);
#   TOOLCHAIN_ROOT: the pinned compiler bundle (the browser lane's home folder).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd -P)
PUBLISHED=$(cd "$2" && pwd -P)
TOOLS=$(cd "$3" && pwd -P)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
sparky_provenance_init sparky-lc-migration:20261020
# The link gate (lean.release check-link) runs when SIBLINGS_DIR (the unpublished libstereo-policy debs, with siblings.txt),
# SPARKY_LC_ARCHIVE_DIR (the public sources.json and keyrings) and SPARKY_REPO_DIR (the published edition tree) are set.
GATE=()
if [ -n "${SIBLINGS_DIR:-}" ]; then
	: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate}" "${SPARKY_REPO_DIR:?the published edition tree}"
	GATE=(--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined
		-v "$SIBLINGS_DIR":/sib:ro -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro -v "$SPARKY_REPO_DIR":/repo:ro
		-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch)
fi
docker run "${SPARKY_PROV_ARGS[@]}" "${GATE[@]}" --rm --ulimit core=0 --name w196-browser --cpus ${BROWSER_JOBS:-8} -e BROWSER_JOBS=${BROWSER_JOBS:-8} --memory 32g --platform linux/amd64 \
	-v "$WORK":/work -v "$PUBLISHED":/in:ro -v "$HERE/browser":/patches:ro -v "$TOOLS":/browser-toolchains:ro \
	-v "$HERE/../..":/toolkit:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	sparky-lc-migration:20261020 bash -c 'sh /run/https-only-apt.sh && bash /toolkit/packages/waterfox-yt3d/build-browser-in-container.sh > /work/build.log 2>&1'
