#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# Build from the published source, the recipe's patch series and this checkout's toolkit.
# Usage: build.sh PUBLISHED.dsc WORK POOL IMAGE ARCHIVE [EXTRA_DEBS]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OS=$(cd "$HERE/../.." && pwd)
. "$OS/repo/build-provenance.sh"
DSC=$(realpath "${1:?published dsc}") WORK=$(realpath -m "${2:?work}")
POOL=$(realpath "${3:?pool}") IMAGE=${4:?image} ARCHIVE=$(realpath "${5:?archive sources.json and public keyrings}")
NAME=$(basename "$HERE")
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$OS/repo/reproducible.py" epoch "$HERE")}
export SPARKY_SOURCE_DATE_BASIS="the newest recipe commit for $NAME"
sparky_provenance_init "$IMAGE" "$HERE"
mkdir -p "$WORK"
EXTRA_MOUNT=()
[ -z "${6:-}" ] || EXTRA_MOUNT=(--mount "type=bind,src=$(realpath "$6"),dst=/extra,readonly")
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:-os16}-$NAME-build" --platform linux/amd64 --cpus 4 --ulimit core=1 \
 --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 "${SPARKY_PROV_ARGS[@]}" -e NAME="$NAME" -e DSC="$(basename "$DSC")" -e OWNER="$(id -u):$(id -g)" \
 --mount "type=bind,src=$OS/..,dst=/recipe,readonly" --mount "type=bind,src=$WORK,dst=/work" \
 --mount "type=bind,src=$(dirname "$DSC"),dst=/published,readonly" --mount "type=bind,src=$POOL,dst=/repo,readonly" \
 --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" "${EXTRA_MOUNT[@]}" \
 --mount "type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly" \
 --mount "type=bind,src=$OS/../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" "$IMAGE" bash -c '
set -euo pipefail
ulimit -c 1
trap '\''chown -R "$OWNER" /work'\'' EXIT
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com DEB_BUILD_OPTIONS=parallel=4
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf "deb [signed-by=/usr/share/keyrings/sparky-stereo-repo.asc] file:/repo mashtabba main\n" > /etc/apt/sources.list.d/stereo.list
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/stereo
apt-get -y update
apt-get -y --no-install-recommends install build-essential debhelper devscripts dpkg-dev python3 deb-multimedia-keyring bubblewrap
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
apt-get -y update
id builder >/dev/null 2>&1 || useradd -u 1000 -m builder
if [ -d /extra ]; then apt-get -y --allow-downgrades install /extra/libplib1t64_*amd64.deb /extra/libplib-dev_*amd64.deb; fi
mkdir -p /work/prepared /work/build /work/link-scratch /work/previous
: > /work/siblings.list
[ ! -d /extra ] || find /extra -maxdepth 1 -name "*.deb" -print > /work/siblings.list
export SPARKY_LC_SIBLINGS_FILE=/work/siblings.list
chown -R builder:builder /work
runuser -u builder -- python3 /recipe/sparky-os/upstream/$NAME/prepare-source.py /published/$DSC /work/prepared
cp /published/*.deb /work/previous/
export SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch SPARKY_LC_PREVIOUS_DIR=/work/previous
cd /work/build
runuser -u builder -- dpkg-source -x /work/prepared/*+lc1.dsc source
apt-get -y --no-install-recommends build-dep ./source
cd source
runuser -u builder -- env SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" SPARKY_LC_PREVIOUS_DIR="$SPARKY_LC_PREVIOUS_DIR" SPARKY_LC_SIBLINGS_FILE="$SPARKY_LC_SIBLINGS_FILE" dpkg-buildpackage -b -us -uc -j4
cd /work/build
PYTHONPATH=/recipe/sparky-os python3 -m lean.release check-debs ./*.deb
'
