#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/10
# Copyright 2026 under the GNU GPL3 License
# ORDER 458b: the next source of our MLT, with the Perl and Ruby bindings, and its amd64 build. The published +lc1 source is unpacked, edit-source.sh
# changes its debian/ (control, rules, two install files), repo/lc-successor.py --in-place --overlay packs the next +lc1 source with this tree's Lean Code
# toolkit, and release/build-from-lc-dsc.sh builds it with the link and start gate and check-debs (every step in a container).
# Usage: build.sh WORK PUBLISHED_DSC ARCH IMAGE REPO
#   WORK           empty folder: source/ (the new .dsc), build/ (the .debs and the build record)
#   PUBLISHED_DSC  mlt_7.40.0-1+stereo3d5+lc1.dsc with its files beside it
#   ARCH IMAGE REPO as build-from-lc-dsc.sh; SPARKY_LC_ARCHIVE_DIR is required as there.
# The date of the source is the recipe's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
. "$TOP/repo/build-provenance.sh"
[ $# -eq 5 ] || { sed -n '/^# Usage/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) DSC=$(realpath "$2") ARCH=$3 IMG=$4 REPO=$(realpath "$5")
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
EPOCH=$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")
mkdir -p "$WORK/source" "$WORK/overlay"
sparky_provenance_init "$IMG" "$HERE"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:-shadowed-458b}-mlt-source" --ulimit core=0 --platform linux/amd64 --user "$(id -u):$(id -g)" -e HOME=/tmp "${SPARKY_PROV_ARGS[@]}" \
	-e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME="Daniel Ramos (Capitain Jack)" -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$(dirname "$DSC")":/published:ro -v "$WORK":/work "$IMG" bash -c '
	set -euo pipefail
	cd /tmp && dpkg-source -x /published/'"$(basename "$DSC")"' tree >/dev/null && cd tree
	bash /recipe/edit-source.sh >/dev/null
	for f in control rules libmlt-perl.install libmlt-ruby.install; do cp debian/$f /work/overlay/$f; done
	cd /tmp && python3 /toolkit/repo/lc-successor.py --in-place --overlay /work/overlay --next 7.40.0-1+stereo3d6 \
		--item "Build MLT'"'"'s Perl and Ruby bindings (ORDER 458b): upstream'"'"'s swig directory builds them (-DSWIG_PERL=ON, -DSWIG_RUBY=ON); new packages libmlt-perl and libmlt-ruby, which load this source'"'"'s libmlt7." \
		--item "libmlt-perl and libmlt-ruby Conflict with and Replace deb-multimedia'"'"'s libmlt7-perl and libmlt7-ruby3.3, which carry the same module files and which the edition'"'"'s pins keep out with their libmlt-7-7; apt swaps them for ours." \
		--source-date-epoch "$SOURCE_DATE_EPOCH" /published/'"$(basename "$DSC")"' /work/source'
NEW=$(ls "$WORK"/source/mlt_*.dsc)
mkdir -p "$WORK/source" && cp "$(dirname "$DSC")"/mlt_7.40.0.orig.tar.gz "$WORK/source/" 2>/dev/null || true
bash "$TOP/release/build-from-lc-dsc.sh" "$NEW" "$ARCH" "$IMG" "$REPO" "$WORK/build"
