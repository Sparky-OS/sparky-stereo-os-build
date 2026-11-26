#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the source of gimp-stereo-pictures 0.3.0-1+lc1 (queue row 137 with row 148, the stereo GIMP's
# milestone 1), the stereo pictures plug-in for GIMP 3. Its upstream is Sparky-OS/PhotoGIMP (branch order137e): the
# commit and the two trees named in source.pin are taken by git archive (the plug-in's folder as plug-in/, without its
# compiled catalogues, which the build makes from the .po files, and its tests as tests/) into the orig tarball, made
# reproducibly (names sorted, the commit's date, owner 0, no extra fields); this folder's debian/ and changelog entry
# are added, then the Lean Code source (lean.debian_prepare). Nothing is built here: build.sh runs
# release/build-from-lc-dsc.sh next.
#   make-source.sh PHOTOGIMP_REPO OUT IMAGE
#   PHOTOGIMP_REPO  a git repository holding the commit of source.pin (a clone of Sparky-OS/PhotoGIMP)
#   OUT             an empty folder: receives the .dsc, the Debian tarball and the orig tarball
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
TOPDIR=gimp-stereo-pictures-0.3.0
mkdir -p "$STAGE/$TOPDIR/plug-in" "$STAGE/$TOPDIR/tests"
git -C "$REPO" archive "$COMMIT:.config/GIMP/3.0/plug-ins/stereo-pictures" | tar -x -C "$STAGE/$TOPDIR/plug-in" --exclude='locale/*/LC_MESSAGES'
git -C "$REPO" archive "$COMMIT:scripts/stereo-pictures-tests" | tar -x -C "$STAGE/$TOPDIR/tests"
WHEN=$(git -C "$REPO" log -1 --format=%ct "$COMMIT")
(cd "$STAGE" && tar --sort=name --mtime="@$WHEN" --owner=0 --group=0 --numeric-owner --format=gnu -cf - "$TOPDIR" | xz -6 -T1 > "$OUT/gimp-stereo-pictures_0.3.0.orig.tar.xz")
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gimp-stereo-pictures}-source-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /out/gimp-stereo-pictures_0.3.0.orig.tar.xz .
	tar -xJf gimp-stereo-pictures_0.3.0.orig.tar.xz
	mv gimp-stereo-pictures-0.3.0 tree
	cp -r /recipe/debian tree/
	python3 - tree/debian/changelog /recipe/changelog-0.3.0-1.txt /recipe/changelog-0.2.0-1.txt <<"CHANGELOG"
import os, sys
from pathlib import Path
sys.path.insert(0, "/toolkit/repo")
import reproducible
entry = Path(sys.argv[2]).read_text()
assert entry.startswith("gimp-stereo-pictures (0.3.0-1) unstable;"), entry[:50]
# the history: 0.2.0-1 as it was published (row 137, milestone 1)
older = Path(sys.argv[3]).read_text()
assert older.startswith("gimp-stereo-pictures (0.2.0-1) unstable;"), older[:50]
trailer = "\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  "
Path(sys.argv[1]).write_text(entry.rstrip("\n") + trailer + reproducible.rfc2822(os.environ["SOURCE_DATE_EPOCH"]) + "\n\n"
                             + older.rstrip("\n") + trailer + "Thu, 26 Nov 2026 12:38:20 +0000\n")
CHANGELOG
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare "$W/tree" 0.3.0-1+lc1 --toolkit /toolkit
	python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" tree
	dpkg-source -b tree >/dev/null
	cp gimp-stereo-pictures_0.3.0-1+lc1.dsc gimp-stereo-pictures_0.3.0-1+lc1.debian.tar.xz /out/
'
ls -la "$OUT"
