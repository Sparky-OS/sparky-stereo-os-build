#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Builds a new upstream source tree with its debian/ through the Lean Code toolkit, the way run-native-batch.py builds
# the inventoried sources: the authored source package first (dpkg-source -b), then, from that .dsc, lean.debian_prepare
# to VERSION (the +lc1 one), the build dependencies from Debian testing with the edition's repository pinned at 1001,
# dpkg-buildpackage -us -uc and lean.release check-debs. Nothing is installed on the host.
#
# Usage: build-dh-lean.sh WORK SOURCE_DIR VERSION REPO
#   WORK        folder holding SOURCE_DIR and its NAME_UPSTREAM.orig.tar.xz (and any NAME_UPSTREAM.orig-COMPONENT.tar.xz,
#               the additional upstream tarballs of a 3.0 (quilt) source, unpacked in SOURCE_DIR/COMPONENT); results land
#               in WORK/out
#   SOURCE_DIR  the unpacked upstream tree with our debian/ (a folder name inside WORK)
#   VERSION     the Lean Code version, debian/changelog's version plus +lc1
#   REPO        the edition's repository (a flat tree with dists/mashtabba), mounted read-only
# IMAGE (default sparky-lc-migration:20261020) and CPUS (default 4) can be set; EXTRA names a folder of .deb files not yet
# in the repository (a library built just before), offered to apt as a flat source above the repository.
# SPARKY_LC_ARCHIVE_DIR (required) is the link gate's folder, mounted at /archive: sources.json, the signed public archives
# with keyring paths under /archive (sparky-os/lean/archive.md), and those keyrings. lean.debhelper runs the link and start
# gate when the packages are built, and it refuses to run without it. SPARKY_LC_PREVIOUS_DIR, when set, is a folder of the
# earlier +lc1 builds the gate compares with (mounted at /prev).
# Last update 2026/11/07
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../repo/build-provenance.sh"
WORK=$(realpath "${1:?work folder}") SRC=${2:?source folder} VERSION=${3:?lc1 version} REPO=$(realpath "${4:?repository}")
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
[ -d "$WORK/$SRC/debian" ] || { echo "no $WORK/$SRC/debian" >&2; exit 2; }
ARCHIVE=$(realpath "${SPARKY_LC_ARCHIVE_DIR:?set SPARKY_LC_ARCHIVE_DIR to the link gate folder: sources.json and its keyrings, mounted at /archive (sparky-os/lean/archive.md)}")
[ -f "$ARCHIVE/sources.json" ] || { echo "no $ARCHIVE/sources.json" >&2; exit 2; }
PREV_MOUNT=() PREV_ENV=()
if [ -n "${SPARKY_LC_PREVIOUS_DIR:-}" ]; then
	PREV_MOUNT=(-v "$(realpath "$SPARKY_LC_PREVIOUS_DIR")":/prev:ro) PREV_ENV=(-e SPARKY_LC_PREVIOUS_DIR=/prev)
fi
mkdir -p "$WORK/out"
# A source is dated by its own newest changelog entry, never by the clock (ORDER 421b); the build record says so.
SOURCE_DATE_EPOCH=$(python3 "$HERE/../repo/reproducible.py" changelog "$WORK/$SRC/debian/changelog")
export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS="the newest changelog entry of $SRC"
sparky_provenance_init "$IMAGE"
NAME=${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lean-dh-$(basename "$SRC" | sed 's/[^A-Za-z0-9_.-]/-/g')
EXTRA_MOUNT=()
[ -n "${EXTRA:-}" ] && EXTRA_MOUNT=(-v "$(realpath "$EXTRA")":/extra-debs:ro)
# the gate isolates each case with bubblewrap, which needs the container's /proc unmasked
docker run --rm --name "$NAME" --platform linux/amd64 --cpus "${CPUS:-4}" --memory 8g \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$ARCHIVE":/archive:ro \
	"${PREV_MOUNT[@]}" "${PREV_ENV[@]}" \
	-v "$WORK":/work -v "$HERE/..":/toolkit:ro -v "$REPO":/repo:ro "${EXTRA_MOUNT[@]}" \
	-e SRC="$SRC" -e VERSION="$VERSION" -e OWNER="$(id -u):$(id -g)" -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com DEB_BUILD_OPTIONS=parallel=4
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/sparky.sources
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/sparky
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install build-essential debhelper devscripts dpkg-dev python3 deb-multimedia-keyring bubblewrap >/dev/null
# the media stack of the edition sits on deb-multimedia (the packaging skill): its build dependencies resolve only with it
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
apt-get -y update >/dev/null
if [ -d /extra-debs ]; then
	mkdir -p /extra && cp /extra-debs/*.deb /extra/ && (cd /extra && dpkg-scanpackages . > Packages 2>/dev/null)
	echo "deb [trusted=yes] file:/extra ./" > /etc/apt/sources.list.d/extra.list
	printf "Package: *\nPin: origin \"\"\nPin-Priority: 1002\n" > /etc/apt/preferences.d/extra
	apt-get -y update >/dev/null
fi
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" "/work/$SRC"
runuser -u builder -- dpkg-source -b "$SRC"
dsc=$(ls /work/*.dsc | grep -v "+lc1" | head -1)
runuser -u builder -- mkdir -p /work/out/authored
cp "$dsc" /work/*.debian.tar.xz /work/*.orig.tar.xz /work/out/authored/
# the additional upstream tarballs of a source with components, which its .dsc lists too
find /work -maxdepth 1 -name "*.orig-*.tar.*" -exec cp {} /work/out/authored/ \;
runuser -u builder -- dpkg-source -x "$dsc" /work/lean-source
runuser -u builder -- env PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lean-source "$VERSION" --toolkit /toolkit
apt-get -y --no-install-recommends build-dep /work/lean-source
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lean-source
cd /work/lean-source
runuser -u builder -- dpkg-buildpackage -us -uc -j4
cp .sparky-lc/source.json /work/out/native-source.json
cd /work
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_*.deb
mv /work/*+lc1* /work/out/
cp /work/*.orig.tar.xz /work/out/
find /work -maxdepth 1 -name "*.orig-*.tar.*" -exec cp {} /work/out/ \;
chown -R "$OWNER" /work
'
