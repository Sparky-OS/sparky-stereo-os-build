#!/bin/bash
# Prepares everything the lab's rows need, once: the guest image, the two kernels, the SDL under test, the audio images and the
# compositor roots. Each step is skipped when its result exists. Needs DOCKER_HOST (the lane socket); apt runs in containers over
# HTTPS only; nothing is installed on the host and no module is loaded on it.
#   prepare.sh WORK SKILLS_CLONE STAGE_AUDIO REPO_TREE
#     WORK         a scratch folder on a solid-state disk with 15 GiB free (kernels, two 1.2 GiB roots, the guests)
#     SKILLS_CLONE a clone of Sparky-OS/sparky-stereo-os (the audio rig files, tools/vkms-stereo-bench)
#     STAGE_AUDIO  a flat apt repository with the sparky-stereo-audio package (the package is staged, not yet published)
#     REPO_TREE    the published tree, read only (its Stereo KWin, Mesa and libsdl3 are "ours")
set -euo pipefail
WORK=$(realpath "$1") SK=$(realpath "$2") STAGE=$(realpath "$3") TREE=$(realpath "$4")
: "${DOCKER_HOST:?set DOCKER_HOST to the lane socket}"
HERE=$(cd "$(dirname "$0")" && pwd)
HELP=/K3D/partners/https-only-apt.sh
mkdir -p "$WORK/kern/ours" "$WORK/kern/stock" "$WORK/guest"
have() { docker image inspect "$1" >/dev/null 2>&1; }
apt_run() { # apt_run NAME OUTDIR COMMAND: a debian:testing container with apt over https, OUTDIR mounted at /out
	docker run --rm --name "$1" --pull=never --ulimit core=0 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
		-v "$HELP":/run/https-only-apt.sh:ro --mount type=bind,src="$2",dst=/out --user 0 debian:testing sh -c "sh /run/https-only-apt.sh >/dev/null; apt-get update -qq; $3"
}
if ! have lab22-guest:1; then
	docker rm -f lab22-build-guest >/dev/null 2>&1 || true
	docker run --name lab22-build-guest --pull=never --ulimit core=0 --cpus 4 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
		-v "$HELP":/run/https-only-apt.sh:ro debian:testing sh -c 'set -e; sh /run/https-only-apt.sh; apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install qemu-system-x86 busybox-static gcc libc6-dev libsdl3-dev libsdl3-0 python3 python3-pil edid-decode cpio xz-utils kmod file pkg-config >/dev/null; apt-get clean'
	docker commit lab22-build-guest lab22-guest:1 >/dev/null; docker rm lab22-build-guest >/dev/null
fi
# the edition's kernel (ours) from the tree, Debian's (stock) from Debian: the unsigned binary and its modules
[ -d "$WORK/kern/ours/x/boot" ] || { mkdir -p "$WORK/kern/ours/x"; dpkg-deb -x "$TREE"/pool/main/l/linux-stereo-base/linux-image-7.3.4-stereo3d18_7.3.4-18+lc1_amd64.deb "$WORK/kern/ours/x"; }
if [ ! -d "$WORK/kern/stock/x/usr/lib/modules" ]; then
	chmod 777 "$WORK/kern/stock"
	apt_run lab22-dl "$WORK/kern/stock" 'cd /tmp; apt-get download linux-binary-unsigned-7.3.4+deb14-amd64 linux-modules-7.3.4+deb14-amd64 >/dev/null 2>&1; cp *.deb /out/; chmod a+r /out/*'
	mkdir -p "$WORK/kern/stock/x"
	for d in "$WORK"/kern/stock/linux-*.deb; do dpkg-deb -x "$d" "$WORK/kern/stock/x"; done
fi
# the SDL3 package of the edition, unpacked (its library goes into the ours guest)
[ -d "$WORK/guest/sdl-ours" ] || { mkdir -p "$WORK/guest/sdl-ours"; dpkg-deb -x "$TREE"/pool/main/libs/libsdl3/libsdl3-0_3.4.18+ds-1+stereo3d4+lc1_amd64.deb "$WORK/guest/sdl-ours"; }
have lab22-audio-stock:1 && have lab22-audio-ours:1 || "$HERE/build-audio.sh" "$SK" "$STAGE" "$TREE"
have lab22-kwin-stock:1 && have lab22-kwin-ours:1 || "$HERE/build-kwin.sh" "$TREE"
for s in ours stock; do [ -d "$WORK/root-$s/usr" ] || "$HERE/export-root.sh" lab22-kwin-$s:1 "$WORK/root-$s"; done
echo "prepared: $WORK"
