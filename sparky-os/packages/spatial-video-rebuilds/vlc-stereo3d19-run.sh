#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# ORDER 265c: run vlc-stereo3d19-build.sh in a container of IMAGE (the published set with VLC Stereo's build dependencies),
# with the build's provenance recorded (build-provenance.sh) and apt over HTTPS only (tools/https-only-apt.sh).
# Usage: SPARKY_LC_ARCHIVE_DIR=DIR vlc-stereo3d19-run.sh IMAGE OUT [REPO]
#   DIR    the link gate's folder, mounted at /archive: sources.json (Debian forky, deb-multimedia forky and the edition's published tree as file:/repo) and the public keyrings it names
#   IMAGE  the container image (its apt sources: the edition at pin 1001 over Debian testing and deb-multimedia)
#   OUT    an empty folder for the build (the packages end in OUT/lc)
#   REPO   the published repository, a folder (default /var/tmp/sparky-repo-current), whose pool holds the +stereo3d16+lc1 source and .deb files
# The recipe's own folder must be committed: the record then says recipeDirty False.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tree=$(cd "$here/../../.." && pwd)
[ -n "${SPARKY_LC_ARCHIVE_DIR:-}" ] || { echo "SPARKY_LC_ARCHIVE_DIR is not set: the link gate's folder (see sparky-os/lean/archive.md)" >&2; exit 2; }
image=${1:?image} out=${2:?out folder} repo=$(readlink -f "${3:-/var/tmp/sparky-repo-current}")
[ -z "$(ls -A "$out" 2>/dev/null)" ] || { echo "$out is not empty" >&2; exit 1; }
mkdir -p "$out/in" "$out/prev" "$out/out"
pool=$repo/pool/main/v/vlc
cp "$pool"/vlc_3.0.24-1+stereo3d16+lc1.dsc "$pool"/vlc_3.0.24-1+stereo3d16+lc1.debian.tar.xz "$pool"/vlc_3.0.24.orig.tar.xz "$pool"/vlc_3.0.24.orig.tar.xz.asc "$out/in/"
cp "$pool"/vlc-stereo_3.0.24-1+stereo3d16+lc1_amd64.deb "$pool"/vlc-stereo-plugin-pipewire_3.0.24-1+stereo3d16+lc1_amd64.deb "$pool"/vlc-stereo-lc-hr_3.0.24-1+stereo3d16+lc1_amd64.deb "$out/prev/"
. "$tree/sparky-os/repo/build-provenance.sh"
sparky_provenance_init "$image" "$here"
docker run --rm --ulimit core=0 --cpus 4 --platform linux/amd64 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/out/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$tree/tools/https-only-apt.sh:/run/https-only-apt.sh:ro" \
	-v "$repo:/repo:ro" -v "$tree/sparky-os:/toolkit:ro" -v "$out/in:/in:ro" -v "$out/prev:/prev:ro" -v "$out/out:/out" \
	-v "$here/vlc-stereo3d19-build.sh:/run/build.sh:ro" --entrypoint "" "$image" bash /run/build.sh
