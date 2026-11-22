#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/22
# Builds the edition's first build of a Debian source with patches of ours, with build-job-stereo3d1.sh:
# plasma-integration 6.7.4-1+stereo3d1+lc1 (queue row 77 milestone 2), or, run as packages/kf6-kirigami/build.sh,
# kf6-kirigami 6.32.0-1+stereo3d1+lc1. The package is the recipe folder's name; its .dsc is pinned below.
# usage: build.sh WORK DEBIAN_SOURCE_DIR DEBIAN_BINARY_DIR PUBLISHED_TREE ARCHIVE_DIR
#   WORK               empty scratch folder for the build
#   DEBIAN_SOURCE_DIR  folder holding Debian's .dsc and its files (snapshot.debian.org at DEBIAN_SNAPSHOT)
#   DEBIAN_BINARY_DIR  folder holding Debian's binary packages of that version (the link gate's predecessor)
#   PUBLISHED_TREE     the edition's published repository (dists/ and pool/)
#   ARCHIVE_DIR        the link gate's archive: sources.json and the keyrings it names
# IMAGE names the builder image (default sparky-lc-migration:20261020); DEBIAN_SNAPSHOT the Debian instant;
# POOL a folder of packages the build may also take (the round's pool), served unsigned; SIBLINGS_DIR a folder of edition
# packages built alongside that the link gate takes as siblings (plasma-integration needs KIconThemes +stereo3d3).
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PACKAGE=$(basename "$HERE")
case $PACKAGE in
plasma-integration) DSC=plasma-integration_6.7.4-1.dsc DSC_SHA256=1a6f4f21f3191a3cc7bed97b096a40b4e1e465b98c61c0977d4fa5a718747f25 VERSION=6.7.4-1+stereo3d1 ;;
kf6-kirigami) DSC=kf6-kirigami_6.32.0-1.dsc DSC_SHA256=304fcf326cc66f1408686817af8b9c355597f3ee66cf69e7294ec4fce40d9ec9 VERSION=6.32.0-1+stereo3d1 ;;
*) echo "no pinned source for $PACKAGE" >&2; exit 2 ;;
esac
WORK=${1:?work folder}; SRC=${2:?Debian source folder}; PREV=${3:?Debian binary folder}; REPO=${4:?published tree}; ARCHIVE=${5:?archive folder}
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
DEBIAN_SNAPSHOT=${DEBIAN_SNAPSHOT:-20261121T150000Z}
NAME=${CONTAINER_NAME:-$PACKAGE-stereo3d1-build}
[[ $DEBIAN_SNAPSHOT =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "DEBIAN_SNAPSHOT must be an instant such as 20261121T150000Z" >&2; exit 2; }
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 2; }
pool=(-e POOL_GIVEN=0); [ -n "${POOL:-}" ] && pool=(-e POOL_GIVEN=1 --mount "type=bind,src=$POOL,dst=/pool,readonly")
# SIBLINGS_DIR: edition packages built alongside (a staged KIconThemes +stereo3d3), supplied to the link gate as siblings
siblings=(); [ -n "${SIBLINGS_DIR:-}" ] && siblings=(--mount "type=bind,src=$SIBLINGS_DIR,dst=/siblings,readonly")
# shellcheck source=../../repo/build-provenance.sh
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$IMAGE" "$HERE"
docker run --name "$NAME" --ulimit core=1 --cpus 4 --platform linux/amd64 --pull=never \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e DEBIAN_SNAPSHOT="$DEBIAN_SNAPSHOT" -e DSC="$DSC" -e DSC_SHA256="$DSC_SHA256" -e VERSION="$VERSION" \
	--mount "type=bind,src=$WORK,dst=/work" \
	--mount "type=bind,src=$SRC,dst=/src,readonly" \
	--mount "type=bind,src=$PREV,dst=/prev,readonly" \
	--mount "type=bind,src=$REPO,dst=/repo,readonly" \
	--mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
	--mount "type=bind,src=$HERE,dst=/recipe,readonly" \
	--mount "type=bind,src=$HERE/../..,dst=/toolkit,readonly" \
	--mount "type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly" \
	--mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	"${pool[@]}" "${siblings[@]}" "$IMAGE" bash -c 'set -e
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
printf "Types: deb\nURIs: https://snapshot.debian.org/archive/debian/%s\nSuites: testing\nComponents: main contrib non-free non-free-firmware\nSigned-By: /usr/share/keyrings/debian-archive-keyring.pgp\nCheck-Valid-Until: no\n" "$DEBIAN_SNAPSHOT" > /etc/apt/sources.list.d/debian.sources
printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /repo/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/edition.sources
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
if [ "$POOL_GIVEN" = 1 ]; then
	printf "Types: deb\nURIs: file:/pool\nSuites: ./\nTrusted: yes\n" > /etc/apt/sources.list.d/pool.sources
	printf "\nPackage: *\nPin: origin \"\"\nPin-Priority: 1002\n" >> /etc/apt/preferences.d/edition
fi
sh /run/https-only-apt.sh
bash /toolkit/packages/plasma-integration/build-job-stereo3d1.sh > /work/job.log 2>&1'
