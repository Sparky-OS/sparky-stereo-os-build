#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Prepare one pinned Debian source, then build its binaries from the resulting .dsc.
# The image must be freshly updated testing with the source's build dependencies and Lean Code tools installed.
# Usage: build.sh SOURCE WORK IMAGE PUBLISHED_TREE ARCHIVE_DIR
# WORK/SOURCE holds the pinned Debian .dsc and every archive it names; ARCHIVE_DIR/sources.json names /repo.
set -euo pipefail
[ $# = 5 ] || { echo 'usage: build.sh SOURCE WORK IMAGE PUBLISHED_TREE ARCHIVE_DIR' >&2; exit 2; }
name=$1
case $name in hplip|xserver-xorg-video-qxl|printing-metas|apt-xapian-index) ;; *) echo "no qualified source preparation for $name" >&2; exit 2 ;; esac
: "${SPARKY_CONTAINER_PREFIX:?set a lane-owned container prefix}"
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
WORK=$(cd "$2" && pwd)
IMAGE=$3
PUBLISHED=$(realpath "$4")
ARCHIVE=$(cd "$5" && pwd)
[ ! -e "$WORK/candidates/$name" ] && [ ! -e "$WORK/binary/$name" ] || {
 echo 'use a fresh work directory; existing source and build outputs are retained' >&2; exit 1;
}
. "$TOOLKIT/repo/build-provenance.sh"
export SPARKY_PROVENANCE_REQUIRED=1
sparky_provenance_init "$IMAGE" "$HERE"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX}build-$name" --platform linux/amd64 --cpus 4 --ulimit core=1 \
 --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
 --user "$(id -u):$(id -g)" "${SPARKY_PROV_ARGS[@]}" \
 -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
 -e SPARKY_LC_SIBLINGS_FILE \
 -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL='Capitain_Jack@yahoo.com' -e DEB_BUILD_OPTIONS=parallel=4 \
 -e NAME="$name" \
 --mount "type=bind,src=$WORK,dst=/work" \
 --mount "type=bind,src=$PUBLISHED,dst=/repo,readonly" \
 --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
 --mount "type=bind,src=$TOOLKIT,dst=/toolkit,readonly" \
 --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
 --mount "type=bind,src=$TOOLKIT/../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
 "$IMAGE" bash -c '
set -euo pipefail
HTTPS_ONLY_APT_CONF=/work/https-only-build.conf sh /run/https-only-apt.sh
export APT_CONFIG=/work/https-only-build.conf
bash /toolkit/packages/carried-from-unstable/prepare.sh "$NAME"
mkdir -p "/work/binary/$NAME"
cd "/work/binary/$NAME"
dsc=(/work/candidates/"$NAME"/*+lc1.dsc)
[ "${#dsc[@]}" = 1 ]
dpkg-source -x "${dsc[0]}" source
cd source
dpkg-buildpackage -b -us -uc -j4
cd ..
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*.deb
'
