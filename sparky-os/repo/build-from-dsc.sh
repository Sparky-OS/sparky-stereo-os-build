#!/bin/bash
#
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Builds one architecture of a source package from its published .dsc, in a throwaway
# container, without touching the source: dpkg-source -x, then dpkg-buildpackage
# (-b on amd64, which also builds the architecture-independent packages; -B elsewhere).
# Every architecture comes from the one source package, so Multi-Arch: same packages
# carry the same changelog and can be installed side by side.
# The .deb, .changes, .buildinfo and build.log land in OUT with a SHA256SUMS, ready for
# update-repo.sh.
#
# Usage: build-from-dsc.sh DSC ARCH IMAGE [JOBS]
#   DSC    the .dsc file name in SRC_DIR (default: SPARKY_REPO_DIR/source)
#   ARCH   amd64 or i386
#   IMAGE  a container image of that architecture with the build tools
#   JOBS   parallel jobs (default 4)
# OUT defaults to SPARKY_STAGING_DIR/<dsc name>-<arch>; FLAGS overrides -b/-B.
# Last update 2026/10/22
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../config/local-config.sh"
[ $# -ge 3 ] || { sed -n '/^# Usage/,/^# Last/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
DSC=$1 ARCH=$2 IMG=$3 JOBS=${4:-4}
case $ARCH in
amd64) FLAGS=${FLAGS:--b} ;;
i386) FLAGS=${FLAGS:--B} ;;
*) echo "unknown architecture $ARCH" >&2; exit 2 ;;
esac
if [ -z "${SRC_DIR:-}" ]; then sparky_need SPARKY_REPO_DIR; SRC_DIR=$SPARKY_REPO_DIR/source; fi
[ -f "$SRC_DIR/$DSC" ] || { echo "$SRC_DIR/$DSC not found" >&2; exit 1; }
sparky_need SPARKY_BUILD_SCRATCH
NAME=${DSC%.dsc}
if [ -z "${OUT:-}" ]; then sparky_need SPARKY_STAGING_DIR; OUT=$SPARKY_STAGING_DIR/$NAME-$ARCH; fi
B=$SPARKY_BUILD_SCRATCH/build-from-dsc/$NAME-$ARCH
rm -rf "$B" "$OUT"; mkdir -p "$B" "$OUT"
docker run --rm --name "build-from-dsc-${NAME//[^A-Za-z0-9_.-]/-}-$ARCH" \
	-v "$SRC_DIR":/src:ro -v "$B":/build -v "$OUT":/out \
	-e DEBIAN_FRONTEND=noninteractive -e DSC="$DSC" -e FLAGS="$FLAGS" -e JOBS="$JOBS" \
	-e OWNER="$(id -u):$(id -g)" "$IMG" bash -c '
	set -e
	cd /build
	dpkg-source -x /src/$DSC tree >/dev/null
	cd tree
	apt-get -qq update >/dev/null 2>&1 || true
	apt-get -y -qq build-dep ./ >/build/build-dep.log 2>&1 || { tail -20 /build/build-dep.log; exit 1; }
	dpkg-buildpackage -us -uc $FLAGS -j$JOBS >/build/build.log 2>&1 || { tail -40 /build/build.log; exit 1; }
	cd /build
	cp *.deb *.changes *.buildinfo build.log /out/
	chown -R "$OWNER" /out /build'
(cd "$OUT" && sha256sum *.deb *.changes *.buildinfo > SHA256SUMS)
sync
echo "$NAME $ARCH: $(ls "$OUT"/*.deb | wc -l) packages in $OUT"
