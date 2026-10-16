#!/bin/sh
# Builds the Sparky Stereo OS beta ISO in containers, the way the beta-iso-lutz lane built beta 1:
#   rootfs  the root file system (rootfs.sh): SparkyLinux 2026.09 KDE's package set on today's Debian testing,
#           the edition's metas with their Recommends, our kernel and Debian's signed one, NVIDIA 615
#   pack    sparkybackup-stereo in a chroot of it (pack.sh): the staged packages, the image's apt sources, the ISO
# Usage: build-beta.sh rootfs|pack|all
# Environment (defaults are the lane's folders):
#   TREE     the root file system (on the build disk)        STAGE   the staged packages, a flat repository
#   REPO     the edition's development repository            CACHE   apt's downloads, outside the tree
#   WORK     the packer's work tree                          OUT     the ISO, its sums, package list, Lean Code manifest
#   SIGNED_MODULES  optional: the DKMS modules signed with the edition's key (sign-modules.sh output); pack only
#   SIGNED_KERNEL   optional: the linux-image package signed with the edition's key (sign-kernel-deb.sh output); pack only
#   LABEL, ISONAME  the menu label and the file name
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ED=$(cd "$HERE/../.." && pwd)
L=/K3D/temp/partners/queue/beta-iso-lutz
TREE=${TREE:-/mnt/build/beta-iso-lutz/rootfs}; STAGE=${STAGE:-/mnt/build/beta-iso-lutz/stage}
REPO=${REPO:-/K3D/temp/sparky-os/repo}; CACHE=${CACHE:-$L/cache}; WORK=${WORK:-$L/pack/work}; OUT=${OUT:-$L/pack/out}
LOGS=${LOGS:-$OUT}
IMAGE=beta-iso-lutz-build:1
docker image inspect $IMAGE >/dev/null 2>&1 || docker build --platform linux/amd64 -t $IMAGE "$HERE"
mkdir -p "$TREE" "$CACHE" "$WORK" "$OUT" "$LOGS"
sm=; [ -n "${SIGNED_MODULES:-}" ] && sm="-v $SIGNED_MODULES:/signed:ro -e SIGNED_MODULES=/signed"
[ -n "${SIGNED_KERNEL:-}" ] && sm="$sm -v $SIGNED_KERNEL:/signed-kernel.deb:ro -e SIGNED_KERNEL=/signed-kernel.deb"
run() {
	# shellcheck disable=SC2086
	docker run --rm --name "beta-iso-lutz-$1" --privileged --cpus 4 --memory 16g \
		-v "$TREE:/rootfs" -v "$CACHE:/cache" -v "$REPO:/repo:ro" -v "$STAGE:/stage" -v "$HERE:/build:ro" \
		-v "$ED/sparky-os/apt:/edition-apt:ro" -v "$ED/sparky-os/lists:/edition-lists:ro" -v "$WORK:/work" -v "$OUT:/out" \
		-e LABEL="${LABEL:-Sparky Stereo OS 9 Mashtabba beta 1}" -e ISONAME="${ISONAME:-sparky-stereo-os-9-mashtabba-beta1-x86_64.iso}" \
		$sm $IMAGE sh -c "$2"
}
case ${1:-all} in
rootfs) run rootfs "/build/stage-index.sh >/dev/null; /build/rootfs.sh all" ;;
pack) run pack "mkdir -p /rootfs/repo /rootfs/stage; /build/pack.sh all" ;;
all) "$0" rootfs && "$0" pack ;;
*) sed -n '2,15p' "$0"; exit 2 ;;
esac
run chown "chown -R $(id -u):$(id -g) /out"
