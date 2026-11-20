#!/bin/bash
# Prepares everything the lab's rows need, once: the guest image, the two kernels, the SDL under test, the audio images and the
# compositor roots. Each step is skipped when its result exists. Needs DOCKER_HOST (the lane socket); apt runs in containers over
# HTTPS only; nothing is installed on the host and no module is loaded on it.
#   prepare.sh WORK SKILLS_CLONE STAGE_AUDIO REPO_TREE [PLASMA_PA_DEB]
#     WORK         a scratch folder on a solid-state disk with 8 GiB free (kernels, two 1.2 GiB roots, the guests; the images take about 6 GiB more in Docker)
#     SKILLS_CLONE a clone of Sparky-OS/sparky-stereo-os (the audio rig files, tools/vkms-stereo-bench)
#     STAGE_AUDIO  a flat apt repository with the sparky-stereo-audio package (the package is staged, not yet published)
#     REPO_TREE    the published tree, read only (its Stereo KWin, Mesa and libsdl3 are "ours")
#     PLASMA_PA_DEB  optional: the edition's plasma-pa .deb with the Sound Quality page (staged, not yet published); without it
#                  the Sound Quality page row is SKIPPED with the reason that its images are not built
set -euo pipefail
[ $# -ge 4 ] || { echo "usage: prepare.sh WORK SKILLS_CLONE STAGE_AUDIO REPO_TREE [PLASMA_PA_DEB]" >&2; exit 2; }
: "${DOCKER_HOST:?set DOCKER_HOST to the Docker the lab may use (it never uses the default one)}"
mkdir -p "$1"
WORK=$(realpath "$1") SK=$(realpath "$2") STAGE=$(realpath "$3") TREE=$(realpath "$4")
[ -f "$STAGE/Packages" ] || { echo "prepare.sh: $STAGE has no Packages file: STAGE_AUDIO must be a flat apt repository (the .deb files and a Packages file made by dpkg-scanpackages)" >&2; exit 2; }
[ -d "$TREE/pool" ] || { echo "prepare.sh: $TREE is not a published tree (no pool folder)" >&2; exit 2; }
[ -f "$SK/skills/audio/bench/rig/proof.py" ] || { echo "prepare.sh: $SK is not a clone of Sparky-OS/sparky-stereo-os (no skills/audio/bench/rig)" >&2; exit 2; }
free=$(df --output=avail -BG "$WORK" | tail -1 | tr -dc 0-9)
[ "$free" -ge 8 ] || { echo "prepare.sh: $WORK has ${free} GiB free, the lab wants 8 GiB there (and about 6 GiB in Docker for its images), on a solid-state disk" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
HELP=/K3D/partners/https-only-apt.sh
# the tree these images are made from: its path and Release date go to WORK/tree.txt, which lab.py prints in the report; a WORK
# made from another round is refused (its roots and images would be of the older tree)
REL=$(sed -n 's/^Date: //p' "$TREE/dists/mashtabba/Release" 2>/dev/null | head -1)
NOW="$TREE ($REL)"
if [ -f "$WORK/tree.txt" ] && [ "$(cat "$WORK/tree.txt")" != "$NOW" ]; then
	echo "prepare.sh: $WORK was prepared against $(cat "$WORK/tree.txt"), not $NOW." >&2
	echo "  Use a new WORK folder and remove the images lab22-kwin-ours:1 lab22-kwin-stock:1 lab22-page-ours:1 lab22-page-stock:1 (docker rmi NAME, by name) so that they are made again." >&2
	exit 2
fi
mkdir -p "$WORK/kern/ours" "$WORK/kern/stock" "$WORK/guest"
have() { docker image inspect "$1" >/dev/null 2>&1; }
apt_run() { # apt_run NAME OUTDIR COMMAND: a debian:testing container with apt over https, OUTDIR mounted at /out
	docker run --rm --name "$1" --pull=never --ulimit core=1 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
		-v "$HELP":/run/https-only-apt.sh:ro --mount type=bind,src="$2",dst=/out --user 0 debian:testing sh -c "sh /run/https-only-apt.sh >/dev/null; apt-get update -qq; $3"
}
if ! have lab22-guest:1; then
	docker rm -f lab22-build-guest >/dev/null 2>&1 || true
	docker run --name lab22-build-guest --pull=never --ulimit core=1 --cpus 4 -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
		-v "$HELP":/run/https-only-apt.sh:ro debian:testing sh -c 'set -e; sh /run/https-only-apt.sh; apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install qemu-system-x86 busybox-static gcc libc6-dev libsdl3-dev libsdl3-0 python3 python3-pil python3-numpy edid-decode cpio xz-utils kmod file pkg-config >/dev/null; apt-get clean'
	docker commit lab22-build-guest lab22-guest:1 >/dev/null; docker rm lab22-build-guest >/dev/null
fi
# the edition's kernel (ours) from the tree, Debian's (stock) from Debian: the unsigned binary and its modules
pick() { # pick GLOB: the newest file of the tree that matches, by version order
	ls "$TREE"/$1 2>/dev/null | sort -V | tail -1
}
if [ ! -d "$WORK/kern/ours/x/boot" ]; then
	KDEB=$(pick 'pool/main/l/linux-stereo-base/linux-image-*-stereo3d*_amd64.deb')
	[ -n "$KDEB" ] || { echo "prepare.sh: no edition kernel (linux-image-*-stereo3d*) in $TREE/pool/main/l/linux-stereo-base" >&2; exit 2; }
	mkdir -p "$WORK/kern/ours/x"; dpkg-deb -x "$KDEB" "$WORK/kern/ours/x"; echo "edition kernel: $(basename "$KDEB")"
fi
if [ ! -d "$WORK/kern/stock/x/usr/lib/modules" ]; then
	chmod 777 "$WORK/kern/stock"
	apt_run lab22-dl "$WORK/kern/stock" 'cd /tmp; apt-get download linux-binary-unsigned-7.3.4+deb14-amd64 linux-modules-7.3.4+deb14-amd64 >/dev/null 2>&1; cp *.deb /out/; chmod a+r /out/*'
	mkdir -p "$WORK/kern/stock/x"
	for d in "$WORK"/kern/stock/linux-*.deb; do dpkg-deb -x "$d" "$WORK/kern/stock/x"; done
fi
# the SDL3 package of the edition, unpacked (its library goes into the ours guest)
if [ ! -d "$WORK/guest/sdl-ours" ]; then
	SDEB=$(pick 'pool/main/libs/libsdl3/libsdl3-0_*+stereo3d*_amd64.deb')
	[ -n "$SDEB" ] || { echo "prepare.sh: no edition libsdl3-0 in $TREE/pool/main/libs/libsdl3" >&2; exit 2; }
	mkdir -p "$WORK/guest/sdl-ours"; dpkg-deb -x "$SDEB" "$WORK/guest/sdl-ours"; echo "edition SDL: $(basename "$SDEB")"
fi
have lab22-audio-stock:1 && have lab22-audio-ours:1 || "$HERE/build-audio.sh" "$SK" "$STAGE" "$TREE"
if [ -n "${5:-}" ]; then
	have lab22-page-stock:1 && have lab22-page-ours:1 || "$HERE/build-page.sh" "$SK" "$5"
fi
have lab22-kwin-stock:1 && have lab22-kwin-ours:1 || "$HERE/build-kwin.sh" "$TREE"
for s in ours stock; do [ -d "$WORK/root-$s/usr" ] || "$HERE/export-root.sh" lab22-kwin-$s:1 "$WORK/root-$s"; done
echo "$NOW" > "$WORK/tree.txt"
echo "prepared: $WORK (against $NOW)"
