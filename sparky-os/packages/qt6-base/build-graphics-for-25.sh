#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Sparky Stereo OS: sparky-stereo-graphics 0.2.19, the Graphics page that asks for qt6-base +stereo3d25 by its exact version
# (every qt6-base build needs a Graphics build, or apt keeps the page back; queue row 121).
# Usage: build-graphics-for-25.sh WORK REPO_DIR ARCHIVE_DIR QT_DEBS_DIR PREVIOUS_SIBLINGS_FILE SIBLINGS_FILE
#   The page's own build.sh runs in the container from a git archive of this checkout's HEAD (WORK/tree), so the source is
#   the committed recipe; QT_DEBS_DIR holds the qt6-base +stereo3d25 packages, installed before the build dependencies.
# Run with the lane's DOCKER_HOST, SPARKY_BUILD_IMAGE and BUILD_NAME_PREFIX; the date is the Graphics recipe's last commit.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GRAPHICS=$(cd "$HERE/../sparky-stereo-graphics" && pwd)
TREE=$(cd "$HERE/../../.." && pwd)
. "$HERE/../../repo/build-provenance.sh"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
REPO=$(realpath "$2") ARCHIVE=$(realpath "$3") QT=$(realpath "$4") PREVSIBS=$(realpath "$5") SIBS=$(realpath "$6")
: "${SPARKY_BUILD_IMAGE:?an owned build image}" "${BUILD_NAME_PREFIX:?an owned container prefix}"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ -z "$(git -C "$TREE" status --porcelain -- sparky-os tools)" ] || { echo "commit the recipe first: the source is HEAD" >&2; exit 1; }
mkdir -p "$WORK/tree" "$WORK/out"
git -C "$TREE" archive HEAD sparky-os tools | tar -x -C "$WORK/tree"
sparky_provenance_init "$SPARKY_BUILD_IMAGE" "$GRAPHICS"
docker run --pull=never --ulimit core=1 --name "${BUILD_NAME_PREFIX}-graphics" --cpus 4 --platform linux/amd64 \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_MIN_FREE_GIB=1 \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
    -e SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/previous-siblings.txt -e SPARKY_LC_SIBLINGS_FILE=/siblings.txt \
    --mount "type=bind,src=$ARCHIVE,dst=/archive,readonly" \
    --mount "type=bind,src=$PREVSIBS,dst=/previous-siblings.txt,readonly" --mount "type=bind,src=$SIBS,dst=/siblings.txt,readonly" \
    --mount "type=bind,src=$WORK,dst=/work" --mount "type=bind,src=$REPO,dst=/repo,readonly" \
    --mount "type=bind,src=$QT,dst=/extra,readonly" \
    --mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
    --mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
    --mount "type=bind,src=$TREE/tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
    "$SPARKY_BUILD_IMAGE" bash -c '
set -euo pipefail
trap "chown -R 1000:1000 /work" EXIT
cp /run/host-ca.crt /etc/ssl/certs/ca-certificates.crt
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
cp /repo/sparky-stereo-repo.asc /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
printf "deb [signed-by=/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc] file:/repo mashtabba main\n" > /etc/apt/sources.list.d/edition.list
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
apt-get -y update > /work/apt-update.log 2>&1
want=()
for f in /extra/*.deb; do case $f in *-dbgsym_*|*-doc*|*-examples_*|*-lc-hr_*|*libqt6sql6-*) ;; *) want+=("$f") ;; esac; done
apt-get -y --no-install-recommends install "${want[@]}" > /work/qt-install.log 2>&1
apt-get -y --no-install-recommends install git python3 cmake extra-cmake-modules gettext libkf6auth-dev libkf6config-dev \
    libkf6coreaddons-dev libkf6i18n-dev libkf6kcmutils-dev libkf6service-dev pkgconf qt6-base-dev qt6-declarative-dev \
    sparky-stereo-problems dpkg-dev bubblewrap > /work/build-dep.log 2>&1
dpkg-query -W libqt6gui6 qt6-base-dev qt6-declarative-dev sparky-stereo-problems > /work/build-versions.txt
mkdir -p "$SPARKY_LC_SCRATCH"
user=$(getent passwd 1000 | cut -d: -f1 || true)
[ -n "$user" ] || { useradd --create-home --uid 1000 builder; user=builder; }
chown -R 1000:1000 /work
cd /work/tree/sparky-os/packages/sparky-stereo-graphics
runuser -u "$user" -- env OUT=/work/out SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" SOURCE_DATE_RFC2822="$SOURCE_DATE_RFC2822" \
    SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    SPARKY_LC_PREVIOUS_SIBLINGS_FILE="$SPARKY_LC_PREVIOUS_SIBLINGS_FILE" SPARKY_LC_SIBLINGS_FILE="$SPARKY_LC_SIBLINGS_FILE" \
    SPARKY_BUILD_INVOCATION="$SPARKY_BUILD_INVOCATION" SPARKY_BUILD_STARTED="$SPARKY_BUILD_STARTED" \
    SPARKY_BUILD_IMAGE_NAME="$SPARKY_BUILD_IMAGE_NAME" SPARKY_BUILD_IMAGE_ID="${SPARKY_BUILD_IMAGE_ID:-}" \
    SPARKY_BUILD_IMAGE_REPO_DIGESTS="${SPARKY_BUILD_IMAGE_REPO_DIGESTS:-}" SPARKY_BUILD_COMMIT="${SPARKY_BUILD_COMMIT:-}" \
    SPARKY_BUILD_DIRTY="${SPARKY_BUILD_DIRTY:-}" SPARKY_SOURCE_DATE_BASIS="$SPARKY_SOURCE_DATE_BASIS" \
    bash ./build.sh > /work/build.log 2>&1
'
