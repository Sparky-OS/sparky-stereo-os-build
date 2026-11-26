#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the first +lc1 source of Celluloid, 0.29-3+stereo3d1 (queue row 137): Debian's 0.29-3 source package
# (checked against source.sha256) unpacked, this folder's patch after Debian's series, the build and run-time dependencies
# of the 3D menu in debian/control, the changelog entry, then the Lean Code source (lean.debian_prepare) packed next to
# Debian's orig tarball. Nothing is built here: release/build-from-lc-dsc.sh builds the .dsc, with the staged gtk4
# +stereo3d3 and mpv-dmo +stereo3d12 packages as its siblings (build.sh does both).
#   make-source.sh DEBIAN_SOURCE OUT IMAGE
#   DEBIAN_SOURCE  a folder with celluloid_0.29-3.dsc, its Debian tarball and celluloid_0.29.orig.tar.gz
#   OUT            an empty folder: receives the new .dsc, its Debian tarball and the orig tarball
#   IMAGE          an image with dpkg-dev and python3 (the build image)
# The date of the source is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^#   make-source/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
SRC=$(realpath "$1") OUT=$(mkdir -p "$2" && cd "$2" && pwd) IMG=$3
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
(cd "$SRC" && sha256sum --check --quiet "$HERE/source.sha256")
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-celluloid}-source-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$SRC":/src:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /src/celluloid_0.29-3.dsc /src/celluloid_0.29-3.debian.tar.xz /src/celluloid_0.29.orig.tar.gz .
	dpkg-source -x celluloid_0.29-3.dsc tree >/dev/null
	cp /recipe/patches/stereo3d-3d-films.patch tree/debian/patches/
	[ -z "$(tail -c1 tree/debian/patches/series)" ] || echo >> tree/debian/patches/series
	echo stereo3d-3d-films.patch >> tree/debian/patches/series
	(cd tree && QUILT_PATCHES=debian/patches dpkg-source --before-build . >/dev/null)
	python3 - tree/debian/control <<"CONTROL"
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
# the stereo area and the render parameter come with these versions; the menu takes its words and the save from the stereo layer
sub(" libgtk-4-dev,\n", " libgtk-4-dev (>= 4.24.1+ds-1+stereo3d3~),\n")
sub(" libmpv-dev (>= 0.32),\n", " libmpv-dev (>= 1:0.41.0-dmo9+stereo3d12~),\n libstereo-av-dev (>= 1.22.0),\n libstereo-policy-dev (>= 1.22.0),\n")
# what the 3D menu runs: libmpv with the stereo view parameter (no symbol says it), mkvpropedit for the save into
# Matroska, kcmshell6 and the display page for "Display Settings" (a dependency a designed feature needs is a Depends)
sub(" ${shlibs:Depends},\nRecommends:", " ${shlibs:Depends},\n libmpv2 (>= 1:0.41.0-dmo9+stereo3d12~),\n mkvtoolnix,\n kde-cli-tools,\n kscreen,\nRecommends:")
p.write_text(s)
CONTROL
	python3 - tree/debian/changelog /recipe/changelog-stereo3d1.txt <<"CHANGELOG"
import os, sys
from pathlib import Path
sys.path.insert(0, "/toolkit/repo")
import reproducible
p = Path(sys.argv[1])
entry = Path(sys.argv[2]).read_text()
assert entry.startswith("celluloid (0.29-3+stereo3d1) unstable;"), entry[:50]
assert p.read_text().startswith("celluloid (0.29-3) ")
p.write_text(entry.rstrip("\n") + "\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  "
             + reproducible.rfc2822(os.environ["SOURCE_DATE_EPOCH"]) + "\n\n" + p.read_text())
CHANGELOG
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare "$W/tree" 0.29-3+stereo3d1+lc1 --toolkit /toolkit
	python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" tree
	dpkg-source -b tree >/dev/null
	cp celluloid_0.29-3+stereo3d1+lc1.dsc celluloid_0.29-3+stereo3d1+lc1.debian.tar.xz celluloid_0.29.orig.tar.gz /out/
'
ls -la "$OUT"
