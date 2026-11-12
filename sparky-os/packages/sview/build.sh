#!/bin/bash
# Sparky Stereo OS: builds sview 26.9+stereo3d5+lc1 from a clone of Sparky-OS/sview, through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/24, +stereo3d2 2026/10/31, +stereo3d3 and +stereo3d4 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# The plain source package is made from the commit (a native package: debian/ is in the tree), then the Lean Code
# source, then the build with the link and start gate against the earlier +lc1 builds, then the one-output check
# (ORDER 312: Stereo KWin's output only), the identity check of lean 0.1.24. Candidates stay in WORK.
# Usage: build.sh WORK PREVIOUS_DIR CLONE [POLICY_DIR]
# POLICY_DIR optionally supplies the matching unpublished libstereo-policy1/dev .debs; it is also a link-gate sibling.
#   (PREVIOUS_DIR: the earlier +lc1 .deb files, an empty folder for a first build; CLONE: a clone holding the commit)
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
CLONE=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
POLICY_ARGS=()
if [ -n "${4:-}" ]; then
	POLICY=$(cd "$4" && pwd)
	POLICY_ARGS=(--mount "type=bind,src=$POLICY,dst=/policy-candidate,readonly")
fi
sparky_provenance_init sparky-lc-migration:20261020
docker run --rm --name "${SPARKY_SVIEW_CONTAINER:-sview-build}" --cpus 4 --platform linux/amd64 --ulimit core=0 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch --mount "type=bind,src=$SPARKY_LC_ARCHIVE_DIR,dst=/archive,readonly" "${POLICY_ARGS[@]}" \
	--mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$PREV,dst=/prev,readonly" --mount "type=bind,src=$SPARKY_REPO_DIR,dst=/repo,readonly" \
	--mount "type=bind,src=$CLONE,dst=/fork,readonly" --mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" --mount "type=bind,src=$HERE,dst=/tools,readonly" \
	--mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	sparky-lc-migration:20261020 bash -c 'sh /run/https-only-apt.sh && bash /tools/build-in-container.sh > /work/build.log 2>&1'
