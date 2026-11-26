#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build ffmpeg-dmo +stereo3d18 for amd64 (and Architecture: all) from its one source package (queue row 916).
# Usage: build-stereo3d18.sh IMAGE WORK PUBLISHED_REPOSITORY
#   WORK/source: the .dsc that make-source-stereo3d18.py wrote, with every file it names;
#   WORK/x265-build: the cohort's libx265-30219 and libx265-dev .debs (ABI 30219 is not published yet);
#   WORK/siblings-ffmpeg.txt and WORK/previous-ffmpeg: the link gate's edition inputs (/repo and /work paths).
# The packages, .buildinfo, .changes and build record land in WORK/ffmpeg-build; the built tree stays in
# WORK/ffmpeg-build/tree for FATE. The i386 twin is handbrake-dmo/build-twin-i386.sh on the same .dsc.
set -euo pipefail
[ "$#" = 3 ] || { sed -n '3,9p' "$0" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(realpath "$2")
REPO=$(realpath "$3")
DSC=$(cd "$WORK/source" && ls ffmpeg-dmo_*+stereo3d18+lc1.dsc)
[ ! -e "$WORK/ffmpeg-build/tree" ] || { echo "$WORK/ffmpeg-build/tree exists" >&2; exit 2; }
mkdir -p "$WORK/ffmpeg-build"
. "$HERE/../../repo/build-provenance.sh"
sparky_provenance_init "$1" "$HERE/../../media/ffmpeg/stereo3d18"
docker run --name "${SPARKY_CONTAINER_PREFIX:-ffmpeg}-ffmpeg18-package" --pull=never \
    --platform linux/amd64 --cpus 4 --ulimit core=1 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e DEB_BUILD_OPTIONS=parallel=4 -e FFMPEG_DSC="$DSC" \
    -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
    -e SPARKY_LC_ARCHIVE_CONFIG=/recipe/archive-sources.json -e SPARKY_LC_SCRATCH=/work/link-ffmpeg \
    -e SPARKY_LC_SIBLINGS_FILE=/work/siblings-ffmpeg.txt -e SPARKY_LC_PREVIOUS_DIR=/work/previous-ffmpeg \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$HERE,dst=/recipe,readonly" \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$HERE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$1" bash -c 'set -eu; sh /run/https-only-apt.sh; export DEBIAN_FRONTEND=noninteractive
id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder
apt-get -y --no-install-recommends install /work/x265-build/libx265-30219_*_amd64.deb /work/x265-build/libx265-dev_*_amd64.deb
runuser -u builder -- dpkg-source -x "/work/source/$FFMPEG_DSC" /work/ffmpeg-build/tree
apt-get -y --no-install-recommends build-dep /work/ffmpeg-build/tree
cd /work/ffmpeg-build/tree
runuser -u builder -- dpkg-buildpackage -b -us -uc -j4
python3 /recipe/check-built.py /work/ffmpeg-build/tree'
