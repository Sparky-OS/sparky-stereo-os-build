#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: builds the next gtk4 after its predecessor: next-source.sh makes the source from the predecessor's
# (+stereo3d2+lc1, published, makes +stereo3d3+lc1, queue row 137 milestone 3; +stereo3d3+lc1, row 137's, makes
# +stereo3d4+lc1, queue row 147 milestone 3), release/build-from-lc-dsc.sh builds it with the Lean Code link and start gate
# against the predecessor's packages. As for +stereo3d2, Debian's own test suite is not run in the build (nocheck: the
# proofs run GTK's tests from the installed gtk-4-tests) and libgtk-4-1-udeb is not built (noudeb: Debian-Installer's
# front end, which the edition's installer does not use, cannot share a link-gate root with libgtk-4-1).
#   build-next.sh WORK PREDECESSOR REPO [IMAGE]
#   WORK         an empty folder: source/ (the new .dsc and its files) and out/ (packages, buildinfo, changes, build record)
#   PREDECESSOR  a folder with one gtk4 +lc1 .dsc, its tarballs and its packages (the published pool folder, or a stage)
#   REPO         the edition's repository, mounted read-only
#   IMAGE        the build image (default sparky-lc-migration:20261020)
# The gate's archive list is this folder's archive-sources.json unless SPARKY_LC_ARCHIVE_DIR names one.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -ge 3 ] || { sed -n '/^#   build-next.sh/,/^# The gate/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) PUB=$(realpath "$2") REPO=$(realpath "$3") IMG=${4:-sparky-lc-migration:20261020}
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
dscs=("$PUB"/gtk4_*+lc1.dsc)
[ "${#dscs[@]}" = 1 ] && [ -f "${dscs[0]}" ] || { echo "$PUB must hold exactly one gtk4 +lc1 source" >&2; exit 2; }
case "$(sed -n 's/^Version: //p' "${dscs[0]}")" in
	4.24.1+ds-1+stereo3d2+lc1) next=4.24.1+ds-1+stereo3d3+lc1 ;;
	4.24.1+ds-1+stereo3d3+lc1) next=4.24.1+ds-1+stereo3d4+lc1 ;;
	*) echo "${dscs[0]}: no next step for this version" >&2; exit 2 ;;
esac
if [ -z "${SPARKY_LC_ARCHIVE_DIR:-}" ]; then
	SPARKY_LC_ARCHIVE_DIR=$WORK/archive
	mkdir -p "$SPARKY_LC_ARCHIVE_DIR"
	cp "$HERE/archive-sources.json" "$SPARKY_LC_ARCHIVE_DIR/sources.json"
	cp /usr/share/keyrings/debian-archive-keyring.pgp /usr/share/keyrings/deb-multimedia-keyring.pgp "$SPARKY_LC_ARCHIVE_DIR/"
	cp "$REPO/sparky-stereo-repo.asc" "$SPARKY_LC_ARCHIVE_DIR/"
fi
export SPARKY_LC_ARCHIVE_DIR
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
mkdir -p "$WORK/source" "$WORK/tmp"
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gtk4}-source-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e TMPDIR=/work/tmp -e SOURCE_DATE_EPOCH="$EPOCH" \
	-v "$TOP/..":/tree:ro -v "$PUB":/published:ro -v "$WORK":/work "$IMG" \
	bash /tree/sparky-os/packages/gtk4/next-source.sh "/published/$(basename "${dscs[0]}")" /work/source
cp "$PUB/gtk4_4.24.1+ds.orig.tar.xz" "$WORK/source/"
rm -rf "$WORK/tmp"
SPARKY_LC_PREVIOUS_DIR="$PUB" SPARKY_DEB_BUILD_OPTIONS=nocheck SPARKY_DEB_BUILD_PROFILES=noudeb \
	bash "$TOP/release/build-from-lc-dsc.sh" "$WORK/source/gtk4_$next.dsc" amd64 "$IMG" "$REPO" "$WORK/out"
