#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# Builds one architecture of a +lc1 source package from its published .dsc, in a throwaway container, with the Lean Code
# link and start gate and lean.release check-debs: every architecture comes from the one source package, so the
# Multi-Arch: same packages carry the same version and the same files under /usr/share (HOUSE-RULES, ORDER 333 and 436).
# The .dsc is the one release/build-dh-lean.sh (or a recipe's make-source) made; nothing here prepares a source.
#
# Usage: build-from-lc-dsc.sh DSC ARCH IMAGE REPO OUT
#   DSC    the +lc1 .dsc (its orig and debian tarballs beside it)
#   ARCH   amd64 or i386
#   IMAGE  a build image of that architecture (sparky-lc-migration:20261020 or :20261020-i386)
#   REPO   the edition's repository (a flat tree with dists/mashtabba), mounted read-only
#   OUT    receives the .deb, .changes, .buildinfo and build-record files and a SHA256SUMS
# SPARKY_LC_ARCHIVE_DIR (sources.json and its keyrings, mounted at /archive) is required, as for build-dh-lean.sh;
# SPARKY_CONTAINER_PREFIX (optional) starts the container name (a lane's own prefix). SPARKY_LC_PREVIOUS_DIR (earlier +lc1 builds the gate compares with) is optional. CPUS (default 4).
# Last update 2026/11/07
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../repo/build-provenance.sh"
[ $# -eq 5 ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
DSC=$(realpath "$1") ARCH=$2 IMG=$3 REPO=$(realpath "$4") OUT=$(realpath -m "$5")
ARCHIVE=$(realpath "${SPARKY_LC_ARCHIVE_DIR:?set SPARKY_LC_ARCHIVE_DIR to the link gate folder (sources.json and its keyrings)}")
case $ARCH in amd64) FLAGS=-b ;; i386) FLAGS=-B ;; *) echo "unknown architecture $ARCH" >&2; exit 2 ;; esac
[ -f "$ARCHIVE/sources.json" ] || { echo "no $ARCHIVE/sources.json" >&2; exit 2; }
PREV_MOUNT=() PREV_ENV=()
if [ -n "${SPARKY_LC_PREVIOUS_DIR:-}" ]; then
	PREV_MOUNT=(-v "$(realpath "$SPARKY_LC_PREVIOUS_DIR")":/prev:ro) PREV_ENV=(-e SPARKY_LC_PREVIOUS_DIR=/prev)
fi
[ ! -e "$OUT" ] || [ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 2; }
mkdir -p "$OUT"
# a source is dated by its own newest changelog entry, never by the clock (ORDER 421b)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tar -xJOf "${DSC%.dsc}.debian.tar.xz" debian/changelog > "$tmp/changelog"
SOURCE_DATE_EPOCH=$(python3 "$HERE/../repo/reproducible.py" changelog "$tmp/changelog")
export SOURCE_DATE_EPOCH SPARKY_SOURCE_DATE_BASIS="the newest changelog entry of $(basename "$DSC")"
sparky_provenance_init "$IMG" "$HERE"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lc-dsc-$(basename "$DSC" .dsc | tr -c 'A-Za-z0-9_.-' -)-$ARCH" --platform "linux/$ARCH" --cpus "${CPUS:-4}" --memory 8g \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$ARCHIVE":/archive:ro \
	"${PREV_MOUNT[@]}" "${PREV_ENV[@]}" \
	-e DSC="$(basename "$DSC")" -e FLAGS="$FLAGS" -e OWNER="$(id -u):$(id -g)" \
	-v "$(dirname "$DSC")":/src:ro -v "$OUT":/work -v "$HERE/..":/toolkit:ro -v "$REPO":/repo:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMG" bash -c '
	set -euo pipefail
	trap "chown -R $OWNER /work" EXIT
	sh /run/https-only-apt.sh
	export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
	cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
	printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/sparky.sources
	printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/sparky
	apt-get -y -qq update >/dev/null
	apt-get -y -qq --no-install-recommends install build-essential debhelper devscripts dpkg-dev python3 deb-multimedia-keyring bubblewrap >/dev/null
	printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
	apt-get -y -qq update >/dev/null
	id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
	mkdir -p /work/link-scratch /work/build && chown -R builder:builder /work
	cd /work/build
	runuser -u builder -- dpkg-source -x /src/$DSC tree >/dev/null
	apt-get -y --no-install-recommends build-dep ./tree >/work/build-dep.log 2>&1 || { tail -20 /work/build-dep.log; exit 1; }
	cd tree
	runuser -u builder -- env SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch dpkg-buildpackage -us -uc $FLAGS -j4
	cd /work/build
	PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/build/*.deb
	mv /work/build/*.deb /work/build/*.changes /work/build/*.buildinfo /work/build/*.sparky-build.json /work/ 2>/dev/null || true
	rm -rf /work/build /work/link-scratch'
(cd "$OUT" && sha256sum *.deb *.changes *.buildinfo > SHA256SUMS)
echo "$(basename "$DSC") $ARCH: $(ls "$OUT"/*.deb | wc -l) packages in $OUT"
