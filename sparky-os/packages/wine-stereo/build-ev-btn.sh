#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# wine 10.0~repack-12+stereo3d8+lc1 (ORDER 15, the winebus EV_BTN patch): the published +stereo3d7+lc1 source plus
# patches/wine-ev-btn-udev.patch and one changelog entry (prepare-ev-btn.py), one source package, then each
# architecture built from that source in a throwaway container with the link and start gate of Lean Code.
#   build-ev-btn.sh source WORK PUBLISHED_DSC             makes WORK/source/wine_*.dsc and its tarballs
#   build-ev-btn.sh build WORK ARCH IMAGE REPO INPUTS      builds ARCH (amd64 or i386) from WORK/source into WORK/out-ARCH
#     INPUTS: the folder of fetch-wine-build-inputs.py (wine-build-inputs, trixie packages with their hashes)
#     REPO: the edition's repository (flat tree with dists/mashtabba), read only
# SPARKY_LC_ARCHIVE_DIR (sources.json and its keyrings, mounted at /archive) is required by the build, as for
# release/build-dh-lean.sh. Nothing is installed on the host.
# Last update 2026/11/07
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
. "$TOP/repo/build-provenance.sh"
NEXT=10.0~repack-12+stereo3d8+lc1
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
case ${1:-} in
source)
	WORK=$(realpath -m "${2:?work folder}") DSC=$(realpath "${3:?published .dsc}")
	[ ! -e "$WORK" ] || [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 2; }
	mkdir -p "$WORK/source"
	STAMP=$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")
	docker run --rm --platform linux/amd64 -e TZ=UTC -e SOURCE_DATE_EPOCH="$STAMP" -e OWNER="$(id -u):$(id -g)" \
		-v "$(dirname "$DSC")":/src:ro -v "$WORK":/work -v "$TOP":/toolkit:ro \
		-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$TOP/../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
		"$IMAGE" bash -c '
		set -euo pipefail
		trap "chown -R $OWNER /work" EXIT
		sh /run/https-only-apt.sh >/dev/null
		export DEBIAN_FRONTEND=noninteractive DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
		apt-get -qq update >/dev/null 2>&1
		apt-get -y -qq --no-install-recommends install quilt devscripts >/dev/null 2>&1
		cd /work
		dpkg-source -x /src/'"$(basename "$DSC")"' tree >/dev/null
		python3 /toolkit/packages/wine-stereo/prepare-ev-btn.py /work/tree '"$NEXT"'
		[ -e /work/wine_10.0~repack.orig.tar.xz ] || ln -s /src/wine_10.0~repack.orig.tar.xz /work/
		dpkg-source -b tree >/dev/null
		mv /work/wine_* /work/source/ 2>/dev/null || true
		cp -L /src/wine_10.0~repack.orig.tar.xz /work/source/ 2>/dev/null || true
		ls /work/source'
	;;
build)
	WORK=$(realpath "${2:?work folder}") ARCH=${3:?amd64 or i386} IMG=${4:?image} REPO=$(realpath "${5:?repository}") INPUTS=$(realpath "${6:?wine-build-inputs}")
	ARCHIVE=$(realpath "${SPARKY_LC_ARCHIVE_DIR:?set SPARKY_LC_ARCHIVE_DIR (sources.json and keyrings)}")
	case $ARCH in amd64) FLAGS=-b ;; i386) FLAGS=-B ;; *) echo "unknown architecture $ARCH" >&2; exit 2 ;; esac
	mkdir -p "$WORK/out-$ARCH"
	export SOURCE_DATE_EPOCH=$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")
	export SPARKY_SOURCE_DATE_BASIS="the last commit touching sparky-os/packages/wine-stereo"
	sparky_provenance_init "$IMG" "$HERE"
	docker run --rm --name "ev-btn-15-wine-$ARCH" --platform "linux/$ARCH" --cpus "${CPUS:-4}" --memory 12g \
		--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
		"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch \
		-e OWNER="$(id -u):$(id -g)" -e FLAGS="$FLAGS" -e ARCH="$ARCH" -e NEXT="$NEXT" -v "$ARCHIVE":/archive:ro \
		-v "$WORK/source":/src:ro -v "$WORK/out-$ARCH":/work -v "$TOP":/toolkit:ro -v "$REPO":/repo:ro -v "$INPUTS":/inputs:ro \
		-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$TOP/../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMG" bash -c '
		set -euo pipefail
		trap "chown -R $OWNER /work" EXIT
		sh /run/https-only-apt.sh >/dev/null
		export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4 DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
		cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
		printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/sparky.sources
		printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/sparky
		mkdir -p /deps && cp /inputs/wine-build-inputs/*_all.deb /inputs/wine-build-inputs/*_$ARCH.deb /deps/ && (cd /deps && dpkg-scanpackages . > Packages 2>/dev/null)
		echo "deb [trusted=yes] file:/deps ./" > /etc/apt/sources.list.d/wine-inputs.list
		printf "Package: unicode-data unicode-idna unicode-cldr-core libldap2-dev libcapi20-dev libcapi20-3t64\nPin: origin \"\"\nPin-Priority: 1002\n" > /etc/apt/preferences.d/wine-inputs
		apt-get -y -qq update >/dev/null 2>&1
		apt-get -y -qq --no-install-recommends install build-essential devscripts bubblewrap quilt python3 deb-multimedia-keyring >/dev/null 2>&1
		printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
		apt-get -y -qq update >/dev/null 2>&1
		id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
		mkdir -p /work/link-scratch /work/build && chown -R builder:builder /work
		cd /work/build
		runuser -u builder -- dpkg-source -x /src/wine_$NEXT.dsc tree >/dev/null
		apt-get -y --no-install-recommends build-dep ./tree > /work/build-dep.log 2>&1 || { tail -20 /work/build-dep.log; exit 1; }
		cd tree
		runuser -u builder -- env SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/work/link-scratch dpkg-buildpackage -us -uc $FLAGS -j4 > /work/build.log 2>&1 || { tail -40 /work/build.log; exit 1; }
		cd /work/build
		PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/build/*.deb
		mv /work/build/*.deb /work/build/*.changes /work/build/*.buildinfo /work/ 2>/dev/null || true'
	;;
*) sed -n '/^# wine/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2 ;;
esac
