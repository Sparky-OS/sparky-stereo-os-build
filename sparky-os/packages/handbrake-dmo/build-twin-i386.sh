#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the i386 twin of one package of Stereo HandBrake's library cohort (x264-dmo, x265-dmo, ffmpeg-dmo) from the
# source package its amd64 build wrote: dpkg-buildpackage -B on the same .dsc, so the changelog and every file under
# /usr/share are the same bytes. Machines with the edition's i386 FFmpeg (Steam, Wine) need the twins, or apt keeps the
# cohort back and Stereo HandBrake runs on the old FFmpeg.
# Usage: build-twin-i386.sh RECIPE_DIR IMAGE_I386 DSC WORK PUBLISHED_REPOSITORY [EXTRA_DEB ...]
#   WORK holds previous/ (the i386 predecessor .debs) and siblings.txt (the link gate's sibling list as /repo and
#   /work paths); the twin is built in WORK/tree and its .debs land in WORK. EXTRA_DEB: i386 archives the build needs
#   before build-dep (the cohort's own i386 libx265-30219 and libx265-dev for FFmpeg), each under WORK.
set -euo pipefail
[ "$#" -ge 5 ] || { sed -n '3,10p' "$0" >&2; exit 2; }
RECIPE=$(cd "$1" && pwd)
IMAGE=$2
DSC=$(realpath "$3")
WORK=$(realpath "$4")
REPO=$(realpath "$5")
shift 5
EXTRA=()
for deb in "$@"; do
	deb=$(realpath "$deb")
	case $deb in "$WORK"/*) EXTRA+=("/work/${deb#"$WORK"/}") ;; *) echo "$deb is not under $WORK" >&2; exit 2 ;; esac
done
[ -d "$WORK/previous" ] && [ -f "$WORK/siblings.txt" ] || { echo "$WORK needs previous/ and siblings.txt" >&2; exit 2; }
[ ! -e "$WORK/tree" ] || { echo "$WORK/tree exists" >&2; exit 2; }
. "$RECIPE/../../repo/build-provenance.sh"
sparky_provenance_init "$IMAGE" "$RECIPE"
docker run --name "${SPARKY_CONTAINER_PREFIX:-twin}-$(basename "$RECIPE")-i386" --rm --pull=never \
	--platform linux/386 --cpus 4 --ulimit core=1 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e DEB_BUILD_OPTIONS=parallel=4 \
	-e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-e SPARKY_LC_ARCHIVE_CONFIG=/recipe/archive-sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
	-e SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt -e SPARKY_LC_PREVIOUS_DIR=/work/previous \
	-e TWIN_DSC="/src/$(basename "$DSC")" -e TWIN_EXTRA="${EXTRA[*]}" \
	--mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
	--mount "type=bind,src=$(dirname "$DSC"),dst=/src,readonly" --mount "type=bind,src=$RECIPE,dst=/recipe,readonly" \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
	--mount "type=bind,src=$RECIPE/../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	"$IMAGE" bash -c 'set -eu; sh /run/https-only-apt.sh; export DEBIAN_FRONTEND=noninteractive
[ "$(dpkg --print-architecture)" = i386 ] || { echo "not an i386 image" >&2; exit 2; }
id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder
runuser -u builder -- dpkg-source -x "$TWIN_DSC" /work/tree
[ -z "$TWIN_EXTRA" ] || apt-get -y --no-install-recommends install $TWIN_EXTRA
apt-get -y --no-install-recommends build-dep /work/tree
mkdir -p /work/link-scratch && chown builder /work/link-scratch
cd /work/tree
runuser -u builder -- dpkg-buildpackage -B -us -uc -j4
if [ -f /recipe/check-built.py ]; then python3 /recipe/check-built.py /work/tree
else cd /work && PYTHONPATH=/work/tree/debian/sparky-lean-toolkit python3 -m lean.release check-debs ./*.deb; fi'
