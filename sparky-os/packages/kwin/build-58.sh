#!/bin/bash
# Sparky Stereo OS: build kwin 4:6.7.4-2+stereo3d58+lc1 from its source (prepare-source-58.sh) through Lean Code, with the link and start
# gate against the earlier +lc1 builds. Created by Daniel Ramos (Capitain Jack) 2026/11/15. Copyright 2026 under the GNU GPL3 License.
# Usage: build-58.sh WORK SOURCE_DIR PREVIOUS_DIR REPO_DIR ARCHIVE_DIR EXTRA_DIR [PREVIOUS_SIBLINGS_FILE]
#   SOURCE_DIR: the folder prepare-source-58.sh wrote (the +58 .dsc and Debian tarball) with the orig tarball and its .asc beside them
#   PREVIOUS_DIR: the earlier +lc1 .deb files of kwin, for the link gate
#   REPO_DIR: the signed published tree the build dependencies come from (dists/mashtabba, read only)
#   ARCHIVE_DIR: the link gate's folder, mounted at /archive: sources.json and the public keyrings it names (sparky-os/lean/archive.md)
#   EXTRA_DIR: staged builds the build needs that the tree does not have yet (plasma-wayland-protocols +stereo3d11 for +57's protocol)
#   PREVIOUS_SIBLINGS_FILE: the published edition's .deb files, one /repo/pool/... path per line, without kwin's own (PREVIOUS_DIR supplies
#   those; the gate refuses two versions of one supplied package)
# SPARKY_KWIN_RESUME=1 resumes a prepared WORK after its package step stopped, with the same SOURCE_DATE_EPOCH: no clean, no new source.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
PREV=$(cd "$3" && pwd)
REPO=$(cd "$4" && pwd)
ARCHIVE=$(cd "$5" && pwd)
EXTRA=$(cd "$6" && pwd)
SIBS=${7:+$(readlink -f "$7")}
if [ "${SPARKY_KWIN_RESUME:-0}" = 1 ]; then
	[ -f "$WORK/lc/source-closure.sha256" ] && [ -d "$WORK/lc/source/obj-x86_64-linux-gnu" ] || { echo "$WORK holds no prepared build to resume" >&2; exit 1; }
else
	[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
fi
sparky_provenance_init "${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}"
docker run --rm --ulimit core=0 --name "${BUILD_NAME_PREFIX:-kwin-58}-kwin" --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_KWIN_RESUME="${SPARKY_KWIN_RESUME:-0}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$ARCHIVE":/archive:ro \
	${SIBS:+-v "$SIBS":/previous-siblings.txt:ro -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt} \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$EXTRA":/extra:ro -v "$REPO":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro -v "$HERE":/tools:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020}" bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container-58.sh >> /work/build.log 2>&1'
