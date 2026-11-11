#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# karton 0.1~prealpha+git20260905.08e13cf-1+stereo3d4: the plain source of the next version, from the published
# +stereo3d3+lc1 source (dpkg-source --skip-patches -x, then plain-from-lc.py), the recipe's patch and series
# (sparky-os/media/karton/stereo3d4) and its changelog entry, dated by the recipe (ORDER 255i).
# release/build-dh-lean.sh WORK karton-tree NEXT+lc1 REPO then builds it.
# Usage: make-plain.sh PUBLISHED_DSC WORK       (WORK is empty or new; the plain tree lands in WORK/karton-tree)
# Last update 2026/11/07
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
RECIPE=$TOP/media/karton/stereo3d4
DSC=$(realpath "${1:?published .dsc}") WORK=$(realpath -m "${2:?work folder}")
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
NEXT=0.1~prealpha+git20260905.08e13cf-1+stereo3d4
[ ! -e "$WORK" ] || [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 2; }
mkdir -p "$WORK"
STAMP=$(python3 "$TOP/repo/reproducible.py" epoch "$RECIPE" "$HERE")
DATE=$(python3 "$TOP/repo/reproducible.py" rfc2822 "$STAMP")
SRC=$(dirname "$DSC")
docker run --rm --platform linux/amd64 -e TZ=UTC -v "$SRC":/src:ro -v "$WORK":/work -v "$TOP":/toolkit:ro -e OWNER="$(id -u):$(id -g)" "$IMAGE" bash -c '
	set -euo pipefail
	trap "chown -R $OWNER /work" EXIT
	cd /work
	dpkg-source --no-copy --skip-patches -x /src/'"$(basename "$DSC")"' tree >/dev/null
	python3 /toolkit/repo/plain-from-lc.py --drop-plan tree
	# patch 0006 installs the catalogs of po/ with ki18n_install(), which compiles them with msgfmt
	python3 - <<PY
import re
p = "tree/debian/control"
s = open(p).read()
assert "gettext" not in s
s, n = re.subn(r"^(Build-Depends: )", r"\\1gettext, ", s, count=1, flags=re.M)
assert n == 1
open(p, "w").write(s)
PY
	cp /src/karton_0.1~prealpha+git20260905.08e13cf.orig.tar.xz /work/
	mv tree karton-tree
'
T=$WORK/karton-tree
mkdir -p "$T/debian/patches/stereo3d"
cp "$RECIPE"/patches/000*.patch "$T/debian/patches/stereo3d/"
cat "$RECIPE/patches/series" >> "$T/debian/patches/series"
{ sed -e "s/@VERSION@/$NEXT/" -e "s/@DATE@/$DATE/" "$RECIPE/changelog.entry"; echo; cat "$T/debian/changelog"; } > "$T/debian/changelog.new"
mv "$T/debian/changelog.new" "$T/debian/changelog"
echo "plain source of $NEXT in $T"
