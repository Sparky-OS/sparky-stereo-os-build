#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the native source of gimp-stereo-pictures 0.2.0+lc1 (queue row 137 with row 148, the stereo GIMP's
# milestone 1), the stereo pictures plug-in for GIMP 3. Its code lives in Sparky-OS/PhotoGIMP (branch order137e): the
# commit and the two trees named in source.pin are taken by git archive (the plug-in's folder as plug-in/, without its
# compiled catalogues, which the build makes from the .po files, and its tests as tests/), this folder's debian/ and
# changelog entry are added, then the Lean Code source (lean.debian_prepare). Nothing is built here: build.sh then runs
# release/build-from-lc-dsc.sh.
#   make-source.sh PHOTOGIMP_REPO OUT IMAGE
#   PHOTOGIMP_REPO  a git repository holding the commit of source.pin (a clone of Sparky-OS/PhotoGIMP)
#   OUT             an empty folder: receives the .dsc and the source tarball
#   IMAGE           an image with dpkg-dev and python3 (the build image)
# The date of the source is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^#   make-source/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
REPO=$(realpath "$1") OUT=$(mkdir -p "$2" && cd "$2" && pwd) IMG=$3
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
COMMIT=$(awk '$2 == "commit" {print $1}' "$HERE/source.pin")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# the commit and each tree must be the pinned ones: a work tree's checkout is never a source
while read -r tree path; do
	[ "$path" = commit ] && continue
	got=$(git -C "$REPO" rev-parse "$COMMIT:$path")
	[ "$got" = "$tree" ] || { echo "$path at $COMMIT is $got, source.pin says $tree" >&2; exit 1; }
done < "$HERE/source.pin"
mkdir -p "$STAGE/tree/plug-in" "$STAGE/tree/tests"
git -C "$REPO" archive "$COMMIT:.config/GIMP/3.0/plug-ins/stereo-pictures" | tar -x -C "$STAGE/tree/plug-in" --exclude='locale/*/LC_MESSAGES'
git -C "$REPO" archive "$COMMIT:scripts/stereo-pictures-tests" | tar -x -C "$STAGE/tree/tests"
cp -r "$HERE/debian" "$STAGE/tree/"
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gimp-stereo-pictures}-source-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$STAGE":/stage:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cp -r /stage/tree "$W/tree"
	cd "$W"
	python3 - tree/debian/changelog /recipe/changelog-0.2.0.txt <<"CHANGELOG"
import os, sys
from pathlib import Path
sys.path.insert(0, "/toolkit/repo")
import reproducible
entry = Path(sys.argv[2]).read_text()
assert entry.startswith("gimp-stereo-pictures (0.2.0) unstable;"), entry[:50]
Path(sys.argv[1]).write_text(entry.rstrip("\n") + "\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  "
                             + reproducible.rfc2822(os.environ["SOURCE_DATE_EPOCH"]) + "\n")
CHANGELOG
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare "$W/tree" 0.2.0+lc1 --toolkit /toolkit
	python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" tree
	dpkg-source -b tree >/dev/null
	cp gimp-stereo-pictures_0.2.0+lc1.dsc gimp-stereo-pictures_0.2.0+lc1.tar.xz /out/
'
ls -la "$OUT"
