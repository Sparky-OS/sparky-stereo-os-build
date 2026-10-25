#!/bin/sh
# Builds the Sparky Stereo OS ISO in containers, the way the beta-iso-lutz lane built beta 1:
#   rootfs  the root file system (rootfs.sh): SparkyLinux 2026.09 KDE's package set on today's Debian testing,
#           the edition's metas with their Recommends, the edition's kernel and no other, NVIDIA 615
#   pack    sparkybackup-stereo in a chroot of it (pack.sh): the staged packages, the image's apt sources, the ISO
#   check   the ISO's boot files, menus, Secure Boot certificate and kernels (check-iso.sh)
# Usage: build-beta.sh rootfs|pack|check|all
# Environment (defaults are the beta 2 work folders):
#   EDITION_REPO  live (default): the published repository at https://repo.sparkyos.org/, as people get it;
#                 flat: the development repository REPO, mounted at /repo
#   ADD_HOSTS     host:address pairs for the containers (docker run --add-host), e.g. a repository host on the LAN
#   IMAGE, NAME   the build image's tag and the containers' name prefix
#   TREE     the root file system (on an SSD)                STAGE   the staged packages, a flat repository
#   REPO     the edition's development repository (flat)     CACHE   apt's downloads, outside the tree
#   WORK     the packer's work tree                          OUT     the ISO, its sums, package list, Lean Code manifest
#   MOKCERT_FILE    optional: the edition's public Secure Boot certificate (DER) the ISO's EFI image carries for
#                   MokManager's "Enroll key from disk"; default: the packer package's copy; pack only
#   SIGNED_MODULES  optional: the DKMS modules signed with the edition's key (sign-modules.sh output); pack only
#   SIGNED_KERNEL   optional: the linux-image package signed with the edition's key (sign-kernel-deb.sh output); pack only
#   LABEL, ISONAME  the menu label and the file name
#   ROOTFSSTEP      base, packages or all (the default); rootfs only
#   PACKSTEP        configure, iso or all (the default); pack only
#   LEAN            1: the packer runs dpkg-stereo's pre-squashfs hook (the Lean Code projection) on the folders it
#                   squashes (default); 0 only for ISO_PURPOSE=benchmark and a -nolean- name
#   OVL             the overlay's upper layer for the iso step (the root file system itself is not changed)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ED=$(cd "$HERE/../.." && pwd)
EDITION_REPO=${EDITION_REPO:-live}
TREE=${TREE:-/mnt/build/beta-iso-lutz/rootfs}; STAGE=${STAGE:-/mnt/build/beta-iso-lutz/stage}
: "${CACHE:=${SPARKY_WORKSPACES:?}/beta-iso-lutz/cache}" "${WORK:=${SPARKY_WORKSPACES:?}/beta-iso-lutz/pack/work}"
: "${OUT:=${SPARKY_WORKSPACES:?}/beta-iso-lutz/pack/out}" "${OVL:=${SPARKY_WORKSPACES:?}/beta-iso-lutz/pack/overlay}"
LOGS=${LOGS:-$OUT}
case "$EDITION_REPO" in
live) REPO=$WORK/no-flat-repository; mkdir -p "$REPO" ;;
flat) REPO=${REPO:-${SPARKY_REPO_DIR:?}} ;;
*) echo "EDITION_REPO must be live or flat"; exit 2 ;;
esac
IMAGE=${IMAGE:-beta-iso-lutz-build:1}; NAME=${NAME:-beta-iso-lutz}
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build --platform linux/amd64 -t "$IMAGE" "$HERE"
mkdir -p "$TREE" "$STAGE" "$CACHE" "$WORK" "$OUT" "$LOGS" "$OVL"
sm=; [ -n "${SIGNED_MODULES:-}" ] && sm="-v $SIGNED_MODULES:/signed:ro -e SIGNED_MODULES=/signed"
[ -n "${SIGNED_KERNEL:-}" ] && sm="$sm -v $SIGNED_KERNEL:/signed-kernel.deb:ro -e SIGNED_KERNEL=/signed-kernel.deb"
[ -n "${MOKCERT_FILE:-}" ] && sm="$sm -v $(readlink -f "$MOKCERT_FILE"):/mokcert.der:ro -e MOKCERT_FILE=/mokcert.der"
sm="$sm -e LEAN=${LEAN:-1} -e ISO_PURPOSE=${ISO_PURPOSE:-release} -e EDITION_REPO=$EDITION_REPO"
for h in ${ADD_HOSTS:-}; do sm="$sm --add-host $h"; done
run() {
	# shellcheck disable=SC2086
	docker run --rm --name "$NAME-$1" --privileged --cpus 4 --memory 16g \
		-v "$TREE:/rootfs" -v "$CACHE:/cache" -v "$REPO:/repo:ro" -v "$STAGE:/stage" -v "$HERE:/build:ro" \
		-v "$ED/sparky-os/apt:/edition-apt:ro" -v "$ED/sparky-os/lists:/edition-lists:ro" -v "$ED/sparky-os/repo:/edition-repo:ro" -v "$WORK:/work" -v "$OUT:/out" -v "$OVL:/overlay" \
		-e LABEL="${LABEL:-Sparky Stereo OS 9 Mashtabba beta 2}" -e ISONAME="${ISONAME:-sparky-stereo-os-9-mashtabba-beta2-x86_64.iso}" \
		$sm "$IMAGE" sh -c "$2"
}
case ${1:-all} in
rootfs) run rootfs "/build/stage-index.sh >/dev/null; /build/rootfs.sh ${ROOTFSSTEP:-all}" ;;
pack) run pack "mkdir -p /rootfs/repo /rootfs/stage; /build/pack.sh ${PACKSTEP:-all}" ;;
check) run check "/build/check-iso.sh /out/${ISONAME:-sparky-stereo-os-9-mashtabba-beta2-x86_64.iso}${MOKCERT_FILE:+ /mokcert.der}" ;;
all) "$0" rootfs && "$0" pack && "$0" check ;;
*) sed -n '2,23p' "$0"; exit 2 ;;
esac
run chown "chown -R $(id -u):$(id -g) /out"
