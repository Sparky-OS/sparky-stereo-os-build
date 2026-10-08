#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The host side of the end-to-end test of sparky-stereo-ffmpeg-fdk: builds the helper package and a stand-in for
# sparky-stereo-apt (the real one needs SparkyLinux's repository), makes the test repositories if they are missing
# (make-test-repos.sh) and runs inside.sh in a container made from the proof base image: debian:testing with
# deb-multimedia configured (media-on-dmo: Dockerfile.proofbase). The container is limited to 4 processors; /var/tmp,
# where the helper builds, is a tmpfs of 12 GB (with exec: docker's default would not run debian/rules), so nothing is left behind; /mnt/noexec is the folder where a build must fail.
# Usage: run-tests.sh [i386]   (T=work folder, IMAGE=the proof base image; FAST=1 skips the sections before the build, STOP_AFTER_4D=1 stops after the question about the build tools, ONLY_4D=1 runs just that question, PREBUILT=file.deb tests that package; the output goes to the terminal)
# Last update 2026/10/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
T=${T:-/mnt/build/mdmo2/fdktest}
IMAGE=${IMAGE:-mdmo-proofbase:1}
PINS=${PINS:-$HERE/../../../apt}
I386=0
[ "${1:-}" = i386 ] && I386=1
mkdir -p "$T/pkgs"
rm -f "$T"/pkgs/*.deb
if [ -n "${PREBUILT:-}" ]; then cp "$PREBUILT" "$T/pkgs/"; else OUT="$T/pkgs" "$HERE/../build.sh" >/dev/null; fi
W=$(mktemp -d "$T/standin.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
mkdir -p "$W/DEBIAN"
cat >"$W/DEBIAN/control" <<EOS
Package: sparky-stereo-apt-standin
Version: 1
Architecture: all
Maintainer: test <test@example.org>
Provides: sparky-stereo-apt
Description: stand-in for sparky-stereo-apt in the test container
EOS
dpkg-deb --root-owner-group -b "$W" "$T/pkgs/sparky-stereo-apt-standin_1_all.deb" >/dev/null
[ -f "$T/repo3/Sources" ] || "$HERE/make-test-repos.sh"
if [ "$I386" = 1 ] && ! grep -q '_i386.deb' "$T/repo2/Packages"; then
	echo "no i386 packages in the test repository; build them first (media-on-dmo)" >&2
	exit 2
fi
exec docker run --rm --name "${NAME:-sparky-fdk-e2e}" --platform linux/amd64 --cpus 4 --tmpfs /var/tmp:rw,exec,mode=1777,size=12g --tmpfs /mnt/noexec:rw,noexec,mode=1777,size=12g --tmpfs /mnt/small:rw,mode=1777,size=1g \
	-v "$T/repo2:/repo2:ro" -v "$T/repo2-no386:/repo2-no386:ro" -v "$T/repo3:/repo3:ro" \
	-v "$T/pkgs:/pkgs:ro" -v "$PINS:/pins:ro" -v "$HERE:/tests:ro" \
	-e I386="$I386" -e FAST="${FAST:-0}" -e STOP_AFTER_4D="${STOP_AFTER_4D:-0}" -e ONLY_4D="${ONLY_4D:-0}" "$IMAGE" bash /tests/inside.sh
