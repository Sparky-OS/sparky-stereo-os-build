#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# libsdl3 3.4.18+ds-1+stereo3d4: the plain source of the next version, from the published +stereo3d3+lc1 source
# (dpkg-source --skip-patches -x, then plain-from-lc.py --build-depends-at-end), the recipe's patches and series
# (sparky-os/media/libsdl3/stereo3d4) and its changelog entry, dated by the recipe (ORDER 421).
# release/build-dh-lean.sh WORK libsdl3-3.4.18+ds NEXT+lc1 REPO then builds it.
# Usage: make-plain.sh PUBLISHED_DSC WORK       (WORK is empty or new; the plain tree lands in WORK/libsdl3-3.4.18+ds)
# Last update 2026/11/07
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
RECIPE=$TOP/media/libsdl3/stereo3d4
DSC=$(realpath "${1:?published .dsc}") WORK=$(realpath -m "${2:?work folder}")
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
NEXT=3.4.18+ds-1+stereo3d4
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
	# the six lc1 build dependencies end a folded Build-Depends, which plain-from-lc.py cannot read: unfold the field for the
	# tool, then put Debian'"'"'s folded form back without them (the same limit as the FFmpeg source, packaging lessons)
	python3 - <<PY
import re
p = "tree/debian/control"
s = open(p).read()
m = re.search(r"^Build-Depends:\n(?: .*\n)+", s, re.M)
folded = m.group(0)
tail = " xxd, gcc, node-acorn, nodejs, perl, python3, python3-yaml\n"
assert folded.endswith(tail), "unexpected end of Build-Depends"
one = "Build-Depends: " + ", ".join(x.strip().rstrip(",") for x in folded.splitlines()[1:]) + "\n"
open(p, "w").write(s.replace(folded, one))
open("/work/folded.txt", "w").write(folded[:-len(tail)] + " xxd\n")
open("/work/one.txt", "w").write(one)
PY
	python3 /toolkit/repo/plain-from-lc.py --build-depends-at-end --drop-plan tree
	python3 - <<PY
import re
p = "tree/debian/control"
s = open(p).read()
m = re.search(r"^Build-Depends: .*\n", s, re.M)
open(p, "w").write(s.replace(m.group(0), open("/work/folded.txt").read()))
PY
	rm -f /work/folded.txt /work/one.txt
	cp /src/libsdl3_3.4.18+ds.orig.tar.xz /work/
	mv tree libsdl3-3.4.18+ds
'
T=$WORK/libsdl3-3.4.18+ds
cp "$RECIPE"/patches/000*.patch "$T/debian/patches/"
cp "$RECIPE/patches/series" "$T/debian/patches/series"
{ sed -e "s/@VERSION@/$NEXT/" -e "s/@DATE@/$DATE/" "$RECIPE/changelog.entry"; echo; cat "$T/debian/changelog"; } > "$T/debian/changelog.new"
mv "$T/debian/changelog.new" "$T/debian/changelog"
echo "plain source of $NEXT in $T"
