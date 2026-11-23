#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Build the Debian source successor with an offline, prepared Debian testing package cache.
# Usage: build.sh DEBIAN_SOURCE_DIR APT_LISTS APT_ARCHIVES EMPTY_OUTPUT_DIR
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(realpath "$here/../..")
source_dir=$(realpath "${1:?Debian source directory}")
apt_lists=$(realpath "${2:?Debian APT lists}")
apt_archives=$(realpath "${3:?Debian APT archives}")
out=$(realpath "${4:?empty output directory}")
image=${SPARKY_BUILD_IMAGE:?Debian testing build image}
ids=${SPARKY_CONTAINER_IDS:?file for recording the stopped build container ID}
name=${SPARKY_CONTAINER_PREFIX:-an851}-build-anacron
cpus=${CPUS:-2}

test -z "$(ls -A "$out")"
. "$toolkit/repo/build-provenance.sh"
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init "$image" "$here"

status=0
docker run -i --name "$name" --pull=never --platform linux/amd64 --network none \
    --cpus "$cpus" --ulimit core=1 "${SPARKY_PROV_ARGS[@]}" \
    --mount "type=bind,src=$toolkit,dst=/toolkit,readonly" \
    --mount "type=bind,src=$source_dir,dst=/source,readonly" \
    --mount "type=bind,src=$apt_lists,dst=/lists,readonly" \
    --mount "type=bind,src=$apt_archives,dst=/archives,readonly" \
    --mount "type=bind,src=$out,dst=/out" \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=${SPARKY_HTTPS_ONLY_APT:?HTTPS-only APT helper},dst=/run/https-only-apt.sh,readonly" \
    -e "BUILD_OWNER=$(id -u):$(id -g)" -e "BUILD_JOBS=$cpus" \
    -e SPARKY_BUILD_REPOSITORY=https://github.com/Sparky-OS/sparky-stereo-os-build \
    "$image" bash -es <<'BUILD' || status=$?
set -euo pipefail
sh /run/https-only-apt.sh
mkdir -p /var/lib/apt/lists /var/cache/apt/archives
cp -a /lists/. /var/lib/apt/lists/
cp /archives/*.deb /var/cache/apt/archives/
export DEBIAN_FRONTEND=noninteractive
apt-get -y --no-download --no-install-recommends install \
    build-essential dpkg-dev debhelper dh-sequence-single-binary python3

export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
mkdir /build
chown "$BUILD_OWNER" /build /out
export PYTHONPATH=/toolkit PYTHONDONTWRITEBYTECODE=1
setpriv --reuid "${BUILD_OWNER%:*}" --regid "${BUILD_OWNER#*:}" --clear-groups bash -es <<'USER'
set -euo pipefail
cd /build
cp /source/anacron_2.3-52.dsc /source/anacron_2.3-52.debian.tar.xz /source/anacron_2.3.orig.tar.gz .
dpkg-source -x anacron_2.3-52.dsc
cd anacron-2.3
# This is a Debian packaging change, so the diff belongs in the Debian tarball.
patch -p1 < /toolkit/packages/anacron/udev-queue-anacron-jobs.patch
{
    printf 'anacron (2.3-52+stereo3d1) unstable; urgency=medium\n\n'
    printf '  * Queue anacron start and stop jobs without waiting in systemd udev events.\n\n'
    printf ' -- %s <%s>  %s\n\n' "$DEBFULLNAME" "$DEBEMAIL" "$SOURCE_DATE_RFC2822"
    cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc -sa "-j$BUILD_JOBS"
cd ..
python3 -c 'import sys; from lean.buildrecord import record; record(sys.argv[1:])' *+stereo3d1_amd64.deb
cp *+stereo3d1* anacron_2.3.orig.tar.gz /out/
USER
BUILD
if docker inspect -f '{{.Id}}' "$name" >> "$ids"; then
    docker rm "$name"
fi
exit "$status"
